//+------------------------------------------------------------------+
//|                                   Donchian_Breakout_Trailing.mq5 |
//|                                                       EA Sonnet  |
//|        Donchian Channel Breakout with ATR Trailing Stop         |
//+------------------------------------------------------------------+
#property copyright "EA Sonnet"
#property version   "1.00"
#property strict

#include "TradeUtils.mqh"

//--- Input parameters
input int      Donchian_Period = 20;          // Donchian Channel Period
input int      ATR_Period = 14;               // ATR Period for Trailing
input double   ATR_Trail_Multiplier = 2.5;    // ATR Trailing Stop Multiplier
input double   Initial_SL_Multiplier = 3.0;   // Initial SL ATR Multiplier
input double   LotSize = 0.01;                // Lot Size
input bool     UseRiskManagement = false;     // Use Risk Management
input double   RiskPercent = 1.0;             // Risk Percent (if enabled)
input int      MagicNumber = 10003;           // Magic Number
input bool     OneTradePerBar = true;         // One Trade Per Bar
input int      MaxPositions = 1;              // Max Concurrent Positions
input bool     CloseOnOpposite = true;        // Close on Opposite Signal

//--- Global variables
CTradeManager *TradeManager;
int handle_atr;
datetime last_trade_bar;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Create trade manager
   TradeManager = new CTradeManager(MagicNumber, LotSize);
   
   //--- Create indicators
   handle_atr = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   
   if(handle_atr == INVALID_HANDLE)
   {
      Print("Failed to create ATR indicator");
      return INIT_FAILED;
   }
   
   last_trade_bar = 0;
   
   Print("Donchian Breakout Trailing EA initialized");
   Print("Donchian Period: ", Donchian_Period);
   Print("ATR Period: ", ATR_Period, " | Trail Mult: ", ATR_Trail_Multiplier);
   
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
   
   Print("Donchian Breakout Trailing EA deinitialized");
}

//+------------------------------------------------------------------+
//| Calculate Donchian Channel High                                  |
//+------------------------------------------------------------------+
double GetDonchianHigh(int period)
{
   double high = 0;
   for(int i = 1; i <= period; i++)
   {
      double bar_high = iHigh(_Symbol, PERIOD_CURRENT, i);
      if(bar_high > high || i == 1) high = bar_high;
   }
   return high;
}

//+------------------------------------------------------------------+
//| Calculate Donchian Channel Low                                   |
//+------------------------------------------------------------------+
double GetDonchianLow(int period)
{
   double low = 0;
   for(int i = 1; i <= period; i++)
   {
      double bar_low = iLow(_Symbol, PERIOD_CURRENT, i);
      if(bar_low < low || i == 1) low = bar_low;
   }
   return low;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Get ATR
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(handle_atr, 0, 0, 2, atr) < 2) return;
   double current_atr = atr[1];
   
   //--- Update trailing stops for existing positions
   ulong tickets[];
   TradeManager.GetPositionTickets(_Symbol, tickets);
   
   for(int i = 0; i < ArraySize(tickets); i++)
   {
      if(PositionSelectByTicket(tickets[i]))
      {
         ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double pos_open = PositionGetDouble(POSITION_PRICE_OPEN);
         double pos_sl = PositionGetDouble(POSITION_SL);
         double pos_tp = PositionGetDouble(POSITION_TP);
         
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         
         if(pos_type == POSITION_TYPE_BUY)
         {
            double new_sl = bid - (current_atr * ATR_Trail_Multiplier);
            if(new_sl > pos_sl && new_sl < bid)
            {
               TradeManager.ModifyPosition(tickets[i], new_sl, pos_tp);
            }
         }
         else if(pos_type == POSITION_TYPE_SELL)
         {
            double new_sl = ask + (current_atr * ATR_Trail_Multiplier);
            if(new_sl < pos_sl || pos_sl == 0)
            {
               if(new_sl > ask)
                  TradeManager.ModifyPosition(tickets[i], new_sl, pos_tp);
            }
         }
      }
   }
   
   //--- Check if new bar (if enabled)
   if(OneTradePerBar)
   {
      if(!IsNewBar(_Symbol, PERIOD_CURRENT, last_trade_bar))
         return;
   }
   
   //--- Calculate Donchian Channels
   double donchian_high = GetDonchianHigh(Donchian_Period);
   double donchian_low = GetDonchianLow(Donchian_Period);
   
   //--- Get current and previous close
   double close_current = iClose(_Symbol, PERIOD_CURRENT, 1);
   double close_prev = iClose(_Symbol, PERIOD_CURRENT, 2);
   
   //--- Check for breakout signals
   bool buy_signal = (close_current > donchian_high) && (close_prev <= donchian_high);
   bool sell_signal = (close_current < donchian_low) && (close_prev >= donchian_low);
   
   //--- Get current price
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   //--- Close opposite positions if enabled
   if(CloseOnOpposite)
   {
      if(buy_signal)
         TradeManager.ClosePositionsByType(_Symbol, POSITION_TYPE_SELL);
      if(sell_signal)
         TradeManager.ClosePositionsByType(_Symbol, POSITION_TYPE_BUY);
   }
   
   //--- Check max positions
   if(TradeManager.CountPositions(_Symbol) >= MaxPositions)
      return;
   
   //--- Buy signal (breakout above Donchian high)
   if(buy_signal)
   {
      double sl = bid - (current_atr * Initial_SL_Multiplier);
      double tp = 0;  // No fixed TP, using trailing stop
      
      double lots = LotSize;
      if(UseRiskManagement)
      {
         double sl_points = current_atr * Initial_SL_Multiplier / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         lots = TradeManager.CalculateLotSize(_Symbol, RiskPercent, sl_points);
      }
      
      TradeManager.OpenBuy(_Symbol, lots, sl, tp, "Donchian_Buy");
      Print("BUY Signal: Breakout above Donchian high (", DoubleToString(donchian_high, 5), ")");
   }
   
   //--- Sell signal (breakout below Donchian low)
   if(sell_signal)
   {
      double sl = ask + (current_atr * Initial_SL_Multiplier);
      double tp = 0;  // No fixed TP, using trailing stop
      
      double lots = LotSize;
      if(UseRiskManagement)
      {
         double sl_points = current_atr * Initial_SL_Multiplier / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         lots = TradeManager.CalculateLotSize(_Symbol, RiskPercent, sl_points);
      }
      
      TradeManager.OpenSell(_Symbol, lots, sl, tp, "Donchian_Sell");
      Print("SELL Signal: Breakout below Donchian low (", DoubleToString(donchian_low, 5), ")");
   }
}
//+------------------------------------------------------------------+