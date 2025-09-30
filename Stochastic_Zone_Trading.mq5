//+------------------------------------------------------------------+
//|                                    Stochastic_Zone_Trading.mq5   |
//|                                                       EA Sonnet  |
//|        Stochastic Overbought/Oversold with Trend Filter         |
//+------------------------------------------------------------------+
#property copyright "EA Sonnet"
#property version   "1.00"
#property strict

#include "TradeUtils.mqh"

//--- Input parameters
input int      Stochastic_K = 14;             // Stochastic %K Period
input int      Stochastic_D = 3;              // Stochastic %D Period
input int      Stochastic_Slowing = 3;        // Stochastic Slowing
input double   Oversold_Level = 20.0;         // Oversold Level
input double   Overbought_Level = 80.0;       // Overbought Level
input int      Trend_EMA_Period = 50;         // Trend Filter EMA
input bool     UseTrendFilter = true;         // Use Trend Filter
input int      ATR_Period = 14;               // ATR Period
input double   ATR_SL_Multiplier = 2.0;       // ATR Stop Loss Multiplier
input double   ATR_TP_Multiplier = 3.0;       // ATR Take Profit Multiplier
input double   LotSize = 0.01;                // Lot Size
input bool     UseRiskManagement = false;     // Use Risk Management
input double   RiskPercent = 1.0;             // Risk Percent (if enabled)
input int      MagicNumber = 10010;           // Magic Number
input bool     OneTradePerBar = true;         // One Trade Per Bar
input int      MaxPositions = 1;              // Max Concurrent Positions

//--- Global variables
CTradeManager *TradeManager;
int handle_stochastic;
int handle_trend_ema;
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
   handle_stochastic = iStochastic(_Symbol, PERIOD_CURRENT, Stochastic_K, Stochastic_D, Stochastic_Slowing, MODE_SMA, STO_LOWHIGH);
   handle_trend_ema = iMA(_Symbol, PERIOD_CURRENT, Trend_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handle_atr = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   
   if(handle_stochastic == INVALID_HANDLE || handle_trend_ema == INVALID_HANDLE || handle_atr == INVALID_HANDLE)
   {
      Print("Failed to create indicators");
      return INIT_FAILED;
   }
   
   last_trade_bar = 0;
   
   Print("Stochastic Zone Trading EA initialized");
   Print("Stochastic: ", Stochastic_K, "/", Stochastic_D, "/", Stochastic_Slowing);
   Print("Zones: Oversold=", Oversold_Level, " Overbought=", Overbought_Level);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicators
   if(handle_stochastic != INVALID_HANDLE) IndicatorRelease(handle_stochastic);
   if(handle_trend_ema != INVALID_HANDLE) IndicatorRelease(handle_trend_ema);
   if(handle_atr != INVALID_HANDLE) IndicatorRelease(handle_atr);
   
   //--- Delete trade manager
   if(TradeManager != NULL) delete TradeManager;
   
   Print("Stochastic Zone Trading EA deinitialized");
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
   double stoch_main[], stoch_signal[], trend_ema[], atr[];
   ArraySetAsSeries(stoch_main, true);
   ArraySetAsSeries(stoch_signal, true);
   ArraySetAsSeries(trend_ema, true);
   ArraySetAsSeries(atr, true);
   
   if(CopyBuffer(handle_stochastic, 0, 0, 3, stoch_main) < 3) return;     // %K
   if(CopyBuffer(handle_stochastic, 1, 0, 3, stoch_signal) < 3) return;   // %D
   if(CopyBuffer(handle_trend_ema, 0, 0, 2, trend_ema) < 2) return;
   if(CopyBuffer(handle_atr, 0, 0, 2, atr) < 2) return;
   
   //--- Get price data
   double close_price = iClose(_Symbol, PERIOD_CURRENT, 1);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double current_atr = atr[1];
   
   //--- Determine trend
   bool uptrend = true;
   bool downtrend = true;
   
   if(UseTrendFilter)
   {
      uptrend = close_price > trend_ema[1];
      downtrend = close_price < trend_ema[1];
   }
   
   //--- Stochastic oversold crossing up (buy signal)
   bool stoch_oversold_cross = (stoch_main[2] < Oversold_Level) && 
                                (stoch_main[1] > Oversold_Level) && 
                                (stoch_main[1] > stoch_signal[1]);
   
   //--- Stochastic overbought crossing down (sell signal)
   bool stoch_overbought_cross = (stoch_main[2] > Overbought_Level) && 
                                  (stoch_main[1] < Overbought_Level) && 
                                  (stoch_main[1] < stoch_signal[1]);
   
   //--- Entry signals with trend filter
   bool buy_signal = stoch_oversold_cross && uptrend;
   bool sell_signal = stoch_overbought_cross && downtrend;
   
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
      
      TradeManager.OpenBuy(_Symbol, lots, sl, tp, "Stoch_Buy");
      Print("BUY Signal: Stochastic exit from oversold zone (", DoubleToString(stoch_main[1], 2), ")");
   }
   
   //--- Sell signal
   if(sell_signal)
   {
      double sl = ask + (current_atr * ATR_SL_Multiplier);
      double tp = ask - (current_atr * ATR_TP_Multiplier);
      
      TradeManager.OpenSell(_Symbol, lots, sl, tp, "Stoch_Sell");
      Print("SELL Signal: Stochastic exit from overbought zone (", DoubleToString(stoch_main[1], 2), ")");
   }
}
//+------------------------------------------------------------------+