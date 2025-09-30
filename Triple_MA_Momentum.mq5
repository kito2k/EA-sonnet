//+------------------------------------------------------------------+
//|                                        Triple_MA_Momentum.mq5    |
//|                                                       EA Sonnet  |
//|   Three MA alignment (5/20/50) with momentum confirmation       |
//+------------------------------------------------------------------+
#property copyright "EA Sonnet"
#property version   "1.00"
#property strict

#include "TradeUtils.mqh"

//--- Input parameters
input int      Fast_MA_Period = 5;            // Fast MA Period
input int      Medium_MA_Period = 20;         // Medium MA Period
input int      Slow_MA_Period = 50;           // Slow MA Period
input ENUM_MA_METHOD MA_Method = MODE_EMA;    // MA Method
input int      ATR_Period = 14;               // ATR Period
input double   ATR_SL_Multiplier = 2.0;       // ATR Stop Loss Multiplier
input double   ATR_TP_Multiplier = 3.5;       // ATR Take Profit Multiplier
input double   LotSize = 0.01;                // Lot Size
input bool     UseRiskManagement = false;     // Use Risk Management
input double   RiskPercent = 1.0;             // Risk Percent (if enabled)
input int      MagicNumber = 10008;           // Magic Number
input bool     OneTradePerBar = true;         // One Trade Per Bar
input int      MaxPositions = 1;              // Max Concurrent Positions
input bool     CloseOnOpposite = true;        // Close on Opposite Signal

//--- Global variables
CTradeManager *TradeManager;
int handle_fast_ma;
int handle_medium_ma;
int handle_slow_ma;
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
   handle_fast_ma = iMA(_Symbol, PERIOD_CURRENT, Fast_MA_Period, 0, MA_Method, PRICE_CLOSE);
   handle_medium_ma = iMA(_Symbol, PERIOD_CURRENT, Medium_MA_Period, 0, MA_Method, PRICE_CLOSE);
   handle_slow_ma = iMA(_Symbol, PERIOD_CURRENT, Slow_MA_Period, 0, MA_Method, PRICE_CLOSE);
   handle_atr = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   
   if(handle_fast_ma == INVALID_HANDLE || handle_medium_ma == INVALID_HANDLE || 
      handle_slow_ma == INVALID_HANDLE || handle_atr == INVALID_HANDLE)
   {
      Print("Failed to create indicators");
      return INIT_FAILED;
   }
   
   last_trade_bar = 0;
   
   Print("Triple MA Momentum EA initialized");
   Print("MAs: ", Fast_MA_Period, "/", Medium_MA_Period, "/", Slow_MA_Period);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicators
   if(handle_fast_ma != INVALID_HANDLE) IndicatorRelease(handle_fast_ma);
   if(handle_medium_ma != INVALID_HANDLE) IndicatorRelease(handle_medium_ma);
   if(handle_slow_ma != INVALID_HANDLE) IndicatorRelease(handle_slow_ma);
   if(handle_atr != INVALID_HANDLE) IndicatorRelease(handle_atr);
   
   //--- Delete trade manager
   if(TradeManager != NULL) delete TradeManager;
   
   Print("Triple MA Momentum EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check if new bar (if enabled)
   if(OneTradePerBar)
   {
      if(!IsNewBar(_Symbol, PERIOD_CURRENT, last_trade_bar))
         return;
   }
   
   //--- Get indicator values
   double fast_ma[], medium_ma[], slow_ma[], atr[];
   ArraySetAsSeries(fast_ma, true);
   ArraySetAsSeries(medium_ma, true);
   ArraySetAsSeries(slow_ma, true);
   ArraySetAsSeries(atr, true);
   
   if(CopyBuffer(handle_fast_ma, 0, 0, 3, fast_ma) < 3) return;
   if(CopyBuffer(handle_medium_ma, 0, 0, 3, medium_ma) < 3) return;
   if(CopyBuffer(handle_slow_ma, 0, 0, 3, slow_ma) < 3) return;
   if(CopyBuffer(handle_atr, 0, 0, 2, atr) < 2) return;
   
   //--- Current alignment
   bool bullish_alignment = (fast_ma[1] > medium_ma[1]) && (medium_ma[1] > slow_ma[1]);
   bool bearish_alignment = (fast_ma[1] < medium_ma[1]) && (medium_ma[1] < slow_ma[1]);
   
   //--- Previous alignment (to detect change)
   bool prev_bullish = (fast_ma[2] > medium_ma[2]) && (medium_ma[2] > slow_ma[2]);
   bool prev_bearish = (fast_ma[2] < medium_ma[2]) && (medium_ma[2] < slow_ma[2]);
   
   //--- Entry signals (when alignment just formed)
   bool buy_signal = bullish_alignment && !prev_bullish;
   bool sell_signal = bearish_alignment && !prev_bearish;
   
   //--- Get current price
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double current_atr = atr[1];
   
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
   
   //--- Calculate lot size
   double lots = LotSize;
   if(UseRiskManagement)
   {
      double sl_points = current_atr * ATR_SL_Multiplier / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      lots = TradeManager.CalculateLotSize(_Symbol, RiskPercent, sl_points);
   }
   
   //--- Buy signal (bullish MA alignment)
   if(buy_signal)
   {
      double sl = bid - (current_atr * ATR_SL_Multiplier);
      double tp = bid + (current_atr * ATR_TP_Multiplier);
      
      TradeManager.OpenBuy(_Symbol, lots, sl, tp, "Triple_MA_Buy");
      Print("BUY Signal: Bullish MA alignment formed");
   }
   
   //--- Sell signal (bearish MA alignment)
   if(sell_signal)
   {
      double sl = ask + (current_atr * ATR_SL_Multiplier);
      double tp = ask - (current_atr * ATR_TP_Multiplier);
      
      TradeManager.OpenSell(_Symbol, lots, sl, tp, "Triple_MA_Sell");
      Print("SELL Signal: Bearish MA alignment formed");
   }
}
//+------------------------------------------------------------------+