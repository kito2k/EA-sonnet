//+------------------------------------------------------------------+
//|                                       CCI_Momentum_Zones.mq5     |
//|                                                       EA Sonnet  |
//|       CCI Zero Line Cross + Extreme Zone Reversals              |
//+------------------------------------------------------------------+
#property copyright "EA Sonnet"
#property version   "1.00"
#property strict

#include "TradeUtils.mqh"

//--- Input parameters
input int      CCI_Period = 14;               // CCI Period
input double   CCI_Overbought = 100.0;        // CCI Overbought Level
input double   CCI_Oversold = -100.0;         // CCI Oversold Level
input bool     TradeZeroCross = true;         // Trade Zero Line Cross
input bool     TradeExtremes = true;          // Trade Extreme Reversals
input int      ATR_Period = 14;               // ATR Period
input double   ATR_SL_Multiplier = 2.0;       // ATR Stop Loss Multiplier
input double   ATR_TP_Multiplier = 3.0;       // ATR Take Profit Multiplier
input double   LotSize = 0.01;                // Lot Size
input bool     UseRiskManagement = false;     // Use Risk Management
input double   RiskPercent = 1.0;             // Risk Percent (if enabled)
input int      MagicNumber = 10012;           // Magic Number
input bool     OneTradePerBar = true;         // One Trade Per Bar
input int      MaxPositions = 2;              // Max Concurrent Positions

//--- Global variables
CTradeManager *TradeManager;
int handle_cci;
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
   handle_cci = iCCI(_Symbol, PERIOD_CURRENT, CCI_Period, PRICE_TYPICAL);
   handle_atr = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   
   if(handle_cci == INVALID_HANDLE || handle_atr == INVALID_HANDLE)
   {
      Print("Failed to create indicators");
      return INIT_FAILED;
   }
   
   last_trade_bar = 0;
   
   Print("CCI Momentum Zones EA initialized");
   Print("CCI Period: ", CCI_Period);
   Print("Zones: Overbought=", CCI_Overbought, " Oversold=", CCI_Oversold);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicators
   if(handle_cci != INVALID_HANDLE) IndicatorRelease(handle_cci);
   if(handle_atr != INVALID_HANDLE) IndicatorRelease(handle_atr);
   
   //--- Delete trade manager
   if(TradeManager != NULL) delete TradeManager;
   
   Print("CCI Momentum Zones EA deinitialized");
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
   double cci[], atr[];
   ArraySetAsSeries(cci, true);
   ArraySetAsSeries(atr, true);
   
   if(CopyBuffer(handle_cci, 0, 0, 3, cci) < 3) return;
   if(CopyBuffer(handle_atr, 0, 0, 2, atr) < 2) return;
   
   //--- Get current price
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double current_atr = atr[1];
   
   //--- Zero line cross signals (momentum)
   bool zero_cross_up = (cci[2] < 0) && (cci[1] > 0);
   bool zero_cross_down = (cci[2] > 0) && (cci[1] < 0);
   
   //--- Extreme reversal signals
   bool extreme_reversal_up = (cci[2] < CCI_Oversold) && (cci[1] > CCI_Oversold);
   bool extreme_reversal_down = (cci[2] > CCI_Overbought) && (cci[1] < CCI_Overbought);
   
   //--- Combine signals based on settings
   bool buy_signal = false;
   bool sell_signal = false;
   
   if(TradeZeroCross)
   {
      buy_signal = buy_signal || zero_cross_up;
      sell_signal = sell_signal || zero_cross_down;
   }
   
   if(TradeExtremes)
   {
      buy_signal = buy_signal || extreme_reversal_up;
      sell_signal = sell_signal || extreme_reversal_down;
   }
   
   //--- Calculate lot size
   double lots = LotSize;
   if(UseRiskManagement)
   {
      double sl_points = current_atr * ATR_SL_Multiplier / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      lots = TradeManager.CalculateLotSize(_Symbol, RiskPercent, sl_points);
   }
   
   //--- Buy signal
   if(buy_signal)
   {
      double sl = bid - (current_atr * ATR_SL_Multiplier);
      double tp = bid + (current_atr * ATR_TP_Multiplier);
      
      string signal_type = zero_cross_up ? "Zero_Cross" : "Oversold_Exit";
      TradeManager.OpenBuy(_Symbol, lots, sl, tp, "CCI_Buy_" + signal_type);
      Print("BUY Signal: CCI ", signal_type, " (", DoubleToString(cci[1], 2), ")");
   }
   
   //--- Sell signal
   if(sell_signal)
   {
      double sl = ask + (current_atr * ATR_SL_Multiplier);
      double tp = ask - (current_atr * ATR_TP_Multiplier);
      
      string signal_type = zero_cross_down ? "Zero_Cross" : "Overbought_Exit";
      TradeManager.OpenSell(_Symbol, lots, sl, tp, "CCI_Sell_" + signal_type);
      Print("SELL Signal: CCI ", signal_type, " (", DoubleToString(cci[1], 2), ")");
   }
}
//+------------------------------------------------------------------+