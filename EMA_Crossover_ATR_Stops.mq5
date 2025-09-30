//+------------------------------------------------------------------+
//|                                      EMA_Crossover_ATR_Stops.mq5 |
//|                                                       EA Sonnet  |
//|              Fast/Slow EMA Crossover with ATR-based SL/TP        |
//+------------------------------------------------------------------+
#property copyright "EA Sonnet"
#property version   "1.00"
#property strict

#include "TradeUtils.mqh"

//--- Input parameters
input int      FastEMA_Period = 12;           // Fast EMA Period
input int      SlowEMA_Period = 26;           // Slow EMA Period
input int      ATR_Period = 14;               // ATR Period
input double   ATR_SL_Multiplier = 2.0;       // ATR Stop Loss Multiplier
input double   ATR_TP_Multiplier = 3.0;       // ATR Take Profit Multiplier
input double   LotSize = 0.01;                // Lot Size
input bool     UseRiskManagement = false;     // Use Risk Management
input double   RiskPercent = 1.0;             // Risk Percent (if enabled)
input int      MagicNumber = 10001;           // Magic Number
input bool     OneTradePerBar = true;         // One Trade Per Bar
input int      MaxPositions = 1;              // Max Concurrent Positions

//--- Global variables
CTradeManager *TradeManager;
int handle_fast_ema;
int handle_slow_ema;
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
   handle_fast_ema = iMA(_Symbol, PERIOD_CURRENT, FastEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handle_slow_ema = iMA(_Symbol, PERIOD_CURRENT, SlowEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handle_atr = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   
   if(handle_fast_ema == INVALID_HANDLE || handle_slow_ema == INVALID_HANDLE || handle_atr == INVALID_HANDLE)
   {
      Print("Failed to create indicators");
      return INIT_FAILED;
   }
   
   last_trade_bar = 0;
   
   Print("EMA Crossover ATR Stops EA initialized");
   Print("Fast EMA: ", FastEMA_Period, " | Slow EMA: ", SlowEMA_Period);
   Print("ATR Period: ", ATR_Period, " | SL Mult: ", ATR_SL_Multiplier, " | TP Mult: ", ATR_TP_Multiplier);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicators
   if(handle_fast_ema != INVALID_HANDLE) IndicatorRelease(handle_fast_ema);
   if(handle_slow_ema != INVALID_HANDLE) IndicatorRelease(handle_slow_ema);
   if(handle_atr != INVALID_HANDLE) IndicatorRelease(handle_atr);
   
   //--- Delete trade manager
   if(TradeManager != NULL) delete TradeManager;
   
   Print("EMA Crossover ATR Stops EA deinitialized");
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
   
   //--- Check max positions
   if(TradeManager.CountPositions(_Symbol) >= MaxPositions)
      return;
   
   //--- Get indicator values
   double fast_ema[], slow_ema[], atr[];
   ArraySetAsSeries(fast_ema, true);
   ArraySetAsSeries(slow_ema, true);
   ArraySetAsSeries(atr, true);
   
   if(CopyBuffer(handle_fast_ema, 0, 0, 3, fast_ema) < 3) return;
   if(CopyBuffer(handle_slow_ema, 0, 0, 3, slow_ema) < 3) return;
   if(CopyBuffer(handle_atr, 0, 0, 2, atr) < 2) return;
   
   //--- Check for crossover signals
   bool bullish_cross = (fast_ema[1] > slow_ema[1]) && (fast_ema[2] <= slow_ema[2]);
   bool bearish_cross = (fast_ema[1] < slow_ema[1]) && (fast_ema[2] >= slow_ema[2]);
   
   //--- Get current price
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double current_atr = atr[1];
   
   //--- Calculate lot size
   double lots = LotSize;
   if(UseRiskManagement)
   {
      double sl_points = current_atr * ATR_SL_Multiplier / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      lots = TradeManager.CalculateLotSize(_Symbol, RiskPercent, sl_points);
   }
   
   //--- Buy signal
   if(bullish_cross)
   {
      double sl = bid - (current_atr * ATR_SL_Multiplier);
      double tp = bid + (current_atr * ATR_TP_Multiplier);
      
      TradeManager.OpenBuy(_Symbol, lots, sl, tp, "EMA_Cross_Buy");
      Print("BUY Signal: Fast EMA crossed above Slow EMA");
   }
   
   //--- Sell signal
   if(bearish_cross)
   {
      double sl = ask + (current_atr * ATR_SL_Multiplier);
      double tp = ask - (current_atr * ATR_TP_Multiplier);
      
      TradeManager.OpenSell(_Symbol, lots, sl, tp, "EMA_Cross_Sell");
      Print("SELL Signal: Fast EMA crossed below Slow EMA");
   }
}
//+------------------------------------------------------------------+