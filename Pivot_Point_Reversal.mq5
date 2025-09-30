//+------------------------------------------------------------------+
//|                                       Pivot_Point_Reversal.mq5   |
//|                                                       EA Sonnet  |
//|         Daily Pivot Points - Trade bounces off S/R levels       |
//+------------------------------------------------------------------+
#property copyright "EA Sonnet"
#property version   "1.00"
#property strict

#include "TradeUtils.mqh"

//--- Input parameters
input double   Pivot_Touch_Threshold = 5.0;   // Pivot Touch Threshold (pips)
input int      RSI_Period = 14;               // RSI Period (confirmation)
input double   RSI_Oversold = 35.0;           // RSI Oversold Level
input double   RSI_Overbought = 65.0;         // RSI Overbought Level
input double   RR_Ratio = 2.0;                // Risk:Reward Ratio
input int      Fixed_SL_Pips = 100;           // Fixed SL (pips)
input double   LotSize = 0.01;                // Lot Size
input bool     UseRiskManagement = false;     // Use Risk Management
input double   RiskPercent = 1.0;             // Risk Percent (if enabled)
input int      MagicNumber = 10007;           // Magic Number
input int      MaxPositions = 3;              // Max Concurrent Positions
input bool     TradeOnlyBounces = true;       // Trade Only Bounces (not breakouts)

//--- Global variables
CTradeManager *TradeManager;
int handle_rsi;

double pivot_point;
double resistance_1, resistance_2, resistance_3;
double support_1, support_2, support_3;
datetime last_pivot_calc_day;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Create trade manager
   TradeManager = new CTradeManager(MagicNumber, LotSize);
   
   //--- Create indicators
   handle_rsi = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   
   if(handle_rsi == INVALID_HANDLE)
   {
      Print("Failed to create RSI indicator");
      return INIT_FAILED;
   }
   
   last_pivot_calc_day = 0;
   
   Print("Pivot Point Reversal EA initialized");
   Print("Pivot Touch Threshold: ", Pivot_Touch_Threshold, " pips");
   Print("RSI Confirmation: Oversold=", RSI_Oversold, " Overbought=", RSI_Overbought);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicators
   if(handle_rsi != INVALID_HANDLE) IndicatorRelease(handle_rsi);
   
   //--- Delete trade manager
   if(TradeManager != NULL) delete TradeManager;
   
   Print("Pivot Point Reversal EA deinitialized");
}

//+------------------------------------------------------------------+
//| Calculate daily pivot points                                     |
//+------------------------------------------------------------------+
void CalculatePivotPoints()
{
   // Get previous daily bar (D1)
   double prev_high = iHigh(_Symbol, PERIOD_D1, 1);
   double prev_low = iLow(_Symbol, PERIOD_D1, 1);
   double prev_close = iClose(_Symbol, PERIOD_D1, 1);
   
   // Classic pivot point formula
   pivot_point = (prev_high + prev_low + prev_close) / 3.0;
   
   // Support levels
   support_1 = (2.0 * pivot_point) - prev_high;
   support_2 = pivot_point - (prev_high - prev_low);
   support_3 = prev_low - 2.0 * (prev_high - pivot_point);
   
   // Resistance levels
   resistance_1 = (2.0 * pivot_point) - prev_low;
   resistance_2 = pivot_point + (prev_high - prev_low);
   resistance_3 = prev_high + 2.0 * (pivot_point - prev_low);
   
   Print("Daily Pivots calculated:");
   Print("  PP: ", pivot_point);
   Print("  R1: ", resistance_1, " R2: ", resistance_2, " R3: ", resistance_3);
   Print("  S1: ", support_1, " S2: ", support_2, " S3: ", support_3);
}

//+------------------------------------------------------------------+
//| Check if price is near a level                                   |
//+------------------------------------------------------------------+
bool IsNearLevel(double price, double level, double threshold_pips)
{
   double threshold = threshold_pips * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return MathAbs(price - level) <= threshold;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Calculate pivots daily
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int current_day = dt.day;
   
   if(last_pivot_calc_day != current_day)
   {
      CalculatePivotPoints();
      last_pivot_calc_day = current_day;
   }
   
   //--- Check if pivots are calculated
   if(pivot_point == 0) return;
   
   //--- Check max positions
   if(TradeManager.CountPositions(_Symbol) >= MaxPositions)
      return;
   
   //--- Get RSI
   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(handle_rsi, 0, 0, 2, rsi) < 2) return;
   
   //--- Get current price
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double close_price = iClose(_Symbol, PERIOD_CURRENT, 0);
   
   //--- Check for support bounce (buy signal)
   bool near_s1 = IsNearLevel(close_price, support_1, Pivot_Touch_Threshold);
   bool near_s2 = IsNearLevel(close_price, support_2, Pivot_Touch_Threshold);
   bool near_s3 = IsNearLevel(close_price, support_3, Pivot_Touch_Threshold);
   
   bool buy_signal = (near_s1 || near_s2 || near_s3) && (rsi[0] < RSI_Oversold);
   
   //--- Check for resistance bounce (sell signal)
   bool near_r1 = IsNearLevel(close_price, resistance_1, Pivot_Touch_Threshold);
   bool near_r2 = IsNearLevel(close_price, resistance_2, Pivot_Touch_Threshold);
   bool near_r3 = IsNearLevel(close_price, resistance_3, Pivot_Touch_Threshold);
   
   bool sell_signal = (near_r1 || near_r2 || near_r3) && (rsi[0] > RSI_Overbought);
   
   //--- Calculate SL/TP
   double sl_distance = Fixed_SL_Pips * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   //--- Calculate lot size
   double lots = LotSize;
   if(UseRiskManagement)
   {
      lots = TradeManager.CalculateLotSize(_Symbol, RiskPercent, Fixed_SL_Pips);
   }
   
   //--- Buy signal (bounce from support)
   if(buy_signal)
   {
      double sl = bid - sl_distance;
      double tp = bid + (sl_distance * RR_Ratio);
      
      string level_name = near_s1 ? "S1" : (near_s2 ? "S2" : "S3");
      
      TradeManager.OpenBuy(_Symbol, lots, sl, tp, "Pivot_Buy_" + level_name);
      Print("BUY Signal: Bounce from support ", level_name, " RSI=", DoubleToString(rsi[0], 2));
   }
   
   //--- Sell signal (bounce from resistance)
   if(sell_signal)
   {
      double sl = ask + sl_distance;
      double tp = ask - (sl_distance * RR_Ratio);
      
      string level_name = near_r1 ? "R1" : (near_r2 ? "R2" : "R3");
      
      TradeManager.OpenSell(_Symbol, lots, sl, tp, "Pivot_Sell_" + level_name);
      Print("SELL Signal: Bounce from resistance ", level_name, " RSI=", DoubleToString(rsi[0], 2));
   }
}
//+------------------------------------------------------------------+