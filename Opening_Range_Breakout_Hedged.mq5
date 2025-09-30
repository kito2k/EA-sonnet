//+------------------------------------------------------------------+
//|                              Opening_Range_Breakout_Hedged.mq5   |
//|                                                       EA Sonnet  |
//|     Opening Range Breakout - First N minutes of trading session |
//+------------------------------------------------------------------+
#property copyright "EA Sonnet"
#property version   "1.00"
#property strict

#include "TradeUtils.mqh"

//--- Input parameters
input int      SessionStart_Hour = 9;         // Session Start Hour (0-23)
input int      SessionStart_Minute = 0;       // Session Start Minute (0-59)
input int      OpeningRange_Minutes = 30;    // Opening Range Duration (minutes)
input int      TradingWindow_Hours = 4;      // Trading Window After Range (hours)
input double   RR_Ratio = 2.0;               // Risk:Reward Ratio
input bool     UseATR_SL = false;             // Use ATR for SL
input int      ATR_Period = 14;               // ATR Period (if enabled)
input double   ATR_SL_Multiplier = 1.5;       // ATR SL Multiplier
input int      Fixed_SL_Points = 150;         // Fixed SL Points (if not using ATR)
input double   LotSize = 0.01;                // Lot Size
input bool     UseRiskManagement = false;     // Use Risk Management
input double   RiskPercent = 1.0;             // Risk Percent (if enabled)
input int      MagicNumber = 10004;           // Magic Number
input int      MaxPositions = 2;              // Max Concurrent Positions
input bool     OneTradePerDirection = true;   // One Trade Per Direction

//--- Global variables
CTradeManager *TradeManager;
int handle_atr;
double range_high;
double range_low;
datetime range_start_time;
datetime range_end_time;
datetime trading_end_time;
bool range_established;
bool buy_trade_taken;
bool sell_trade_taken;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Create trade manager
   TradeManager = new CTradeManager(MagicNumber, LotSize);
   
   //--- Create indicators
   if(UseATR_SL)
   {
      handle_atr = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
      if(handle_atr == INVALID_HANDLE)
      {
         Print("Failed to create ATR indicator");
         return INIT_FAILED;
      }
   }
   
   range_high = 0;
   range_low = 0;
   range_established = false;
   buy_trade_taken = false;
   sell_trade_taken = false;
   
   Print("Opening Range Breakout EA initialized");
   Print("Session Start: ", SessionStart_Hour, ":", SessionStart_Minute);
   Print("Opening Range: ", OpeningRange_Minutes, " minutes");
   Print("Trading Window: ", TradingWindow_Hours, " hours");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicators
   if(handle_atr != INVALID_HANDLE) IndicatorRelease(handle_atr);
   
   //--- Delete trade manager
   if(TradeManager != NULL) delete TradeManager;
   
   Print("Opening Range Breakout EA deinitialized");
}

//+------------------------------------------------------------------+
//| Check if within opening range period                             |
//+------------------------------------------------------------------+
bool IsWithinOpeningRange(datetime current_time)
{
   MqlDateTime dt;
   TimeToStruct(current_time, dt);
   
   // Check if we're at session start
   if(dt.hour == SessionStart_Hour && dt.min >= SessionStart_Minute)
   {
      if(!range_established)
      {
         range_start_time = current_time;
         range_end_time = range_start_time + (OpeningRange_Minutes * 60);
         trading_end_time = range_end_time + (TradingWindow_Hours * 3600);
         range_established = false;
      }
   }
   
   if(current_time >= range_start_time && current_time < range_end_time)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Calculate opening range                                          |
//+------------------------------------------------------------------+
void CalculateOpeningRange()
{
   range_high = 0;
   range_low = 999999;
   
   datetime current_time = TimeCurrent();
   
   for(int i = 0; i < 1000; i++)
   {
      datetime bar_time = iTime(_Symbol, PERIOD_M1, i);
      
      if(bar_time >= range_start_time && bar_time < range_end_time)
      {
         double high = iHigh(_Symbol, PERIOD_M1, i);
         double low = iLow(_Symbol, PERIOD_M1, i);
         
         if(high > range_high) range_high = high;
         if(low < range_low) range_low = low;
      }
      
      if(bar_time < range_start_time)
         break;
   }
   
   if(range_high > 0 && range_low < 999999)
   {
      range_established = true;
      Print("Opening Range established: High=", range_high, " Low=", range_low);
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime current_time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(current_time, dt);
   
   //--- Reset daily tracking at session start
   if(dt.hour == SessionStart_Hour && dt.min == SessionStart_Minute && dt.sec < 10)
   {
      range_established = false;
      buy_trade_taken = false;
      sell_trade_taken = false;
      range_high = 0;
      range_low = 0;
   }
   
   //--- Build opening range
   if(IsWithinOpeningRange(current_time))
   {
      return;  // Just accumulate range, don't trade yet
   }
   
   //--- Calculate range if just ended
   if(!range_established && current_time >= range_end_time && range_end_time > 0)
   {
      CalculateOpeningRange();
   }
   
   //--- Check if within trading window
   if(!range_established || current_time > trading_end_time)
      return;
   
   //--- Check max positions
   if(TradeManager.CountPositions(_Symbol) >= MaxPositions)
      return;
   
   //--- Get current price
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   //--- Check for breakout signals
   bool buy_signal = (bid > range_high) && (!buy_trade_taken || !OneTradePerDirection);
   bool sell_signal = (ask < range_low) && (!sell_trade_taken || !OneTradePerDirection);
   
   //--- Calculate SL distance
   double sl_distance = 0;
   if(UseATR_SL)
   {
      double atr[];
      ArraySetAsSeries(atr, true);
      if(CopyBuffer(handle_atr, 0, 0, 2, atr) >= 2)
      {
         sl_distance = atr[1] * ATR_SL_Multiplier;
      }
   }
   else
   {
      sl_distance = PointsToPrice(_Symbol, Fixed_SL_Points);
   }
   
   //--- Buy signal (breakout above range high)
   if(buy_signal)
   {
      double sl = bid - sl_distance;
      double tp = bid + (sl_distance * RR_Ratio);
      
      double lots = LotSize;
      if(UseRiskManagement)
      {
         double sl_points = sl_distance / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         lots = TradeManager.CalculateLotSize(_Symbol, RiskPercent, sl_points);
      }
      
      if(TradeManager.OpenBuy(_Symbol, lots, sl, tp, "OR_Breakout_Buy"))
      {
         buy_trade_taken = true;
         Print("BUY Signal: Breakout above opening range high (", DoubleToString(range_high, 5), ")");
      }
   }
   
   //--- Sell signal (breakout below range low)
   if(sell_signal)
   {
      double sl = ask + sl_distance;
      double tp = ask - (sl_distance * RR_Ratio);
      
      double lots = LotSize;
      if(UseRiskManagement)
      {
         double sl_points = sl_distance / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         lots = TradeManager.CalculateLotSize(_Symbol, RiskPercent, sl_points);
      }
      
      if(TradeManager.OpenSell(_Symbol, lots, sl, tp, "OR_Breakout_Sell"))
      {
         sell_trade_taken = true;
         Print("SELL Signal: Breakout below opening range low (", DoubleToString(range_low, 5), ")");
      }
   }
}
//+------------------------------------------------------------------+