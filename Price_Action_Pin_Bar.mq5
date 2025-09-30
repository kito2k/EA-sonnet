//+------------------------------------------------------------------+
//|                                     Price_Action_Pin_Bar.mq5     |
//|                                                       EA Sonnet  |
//|         Pin Bar Detection (Hammer/Shooting Star) Reversal       |
//+------------------------------------------------------------------+
#property copyright "EA Sonnet"
#property version   "1.00"
#property strict

#include "TradeUtils.mqh"

//--- Input parameters
input double   Min_Pin_Body_Ratio = 0.33;     // Max Body/Total Ratio (0-1)
input double   Min_Wick_Body_Ratio = 2.0;     // Min Wick/Body Ratio
input int      Trend_EMA_Period = 50;         // Trend Filter EMA
input bool     UseTrendFilter = true;         // Use Trend Filter
input int      ATR_Period = 14;               // ATR Period
input double   ATR_SL_Multiplier = 1.5;       // ATR Stop Loss Multiplier
input double   RR_Ratio = 2.5;                // Risk:Reward Ratio
input double   LotSize = 0.01;                // Lot Size
input bool     UseRiskManagement = false;     // Use Risk Management
input double   RiskPercent = 1.0;             // Risk Percent (if enabled)
input int      MagicNumber = 10011;           // Magic Number
input bool     OneTradePerBar = true;         // One Trade Per Bar
input int      MaxPositions = 1;              // Max Concurrent Positions

//--- Global variables
CTradeManager *TradeManager;
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
   handle_trend_ema = iMA(_Symbol, PERIOD_CURRENT, Trend_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handle_atr = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   
   if(handle_trend_ema == INVALID_HANDLE || handle_atr == INVALID_HANDLE)
   {
      Print("Failed to create indicators");
      return INIT_FAILED;
   }
   
   last_trade_bar = 0;
   
   Print("Price Action Pin Bar EA initialized");
   Print("Pin Bar: Body ratio max=", Min_Pin_Body_Ratio, " Wick/Body min=", Min_Wick_Body_Ratio);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicators
   if(handle_trend_ema != INVALID_HANDLE) IndicatorRelease(handle_trend_ema);
   if(handle_atr != INVALID_HANDLE) IndicatorRelease(handle_atr);
   
   //--- Delete trade manager
   if(TradeManager != NULL) delete TradeManager;
   
   Print("Price Action Pin Bar EA deinitialized");
}

//+------------------------------------------------------------------+
//| Check for bullish pin bar (hammer)                               |
//+------------------------------------------------------------------+
bool IsBullishPinBar(int shift)
{
   double open = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double high = iHigh(_Symbol, PERIOD_CURRENT, shift);
   double low = iLow(_Symbol, PERIOD_CURRENT, shift);
   double close = iClose(_Symbol, PERIOD_CURRENT, shift);
   
   double total_range = high - low;
   if(total_range == 0) return false;
   
   double body = MathAbs(close - open);
   double upper_wick = high - MathMax(open, close);
   double lower_wick = MathMin(open, close) - low;
   
   // Body must be small relative to total range
   double body_ratio = body / total_range;
   if(body_ratio > Min_Pin_Body_Ratio) return false;
   
   // Lower wick must be significantly larger than body
   if(body == 0) return false;
   double wick_body_ratio = lower_wick / body;
   if(wick_body_ratio < Min_Wick_Body_Ratio) return false;
   
   // Upper wick should be small
   if(upper_wick > body * 0.5) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for bearish pin bar (shooting star)                        |
//+------------------------------------------------------------------+
bool IsBearishPinBar(int shift)
{
   double open = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double high = iHigh(_Symbol, PERIOD_CURRENT, shift);
   double low = iLow(_Symbol, PERIOD_CURRENT, shift);
   double close = iClose(_Symbol, PERIOD_CURRENT, shift);
   
   double total_range = high - low;
   if(total_range == 0) return false;
   
   double body = MathAbs(close - open);
   double upper_wick = high - MathMax(open, close);
   double lower_wick = MathMin(open, close) - low;
   
   // Body must be small relative to total range
   double body_ratio = body / total_range;
   if(body_ratio > Min_Pin_Body_Ratio) return false;
   
   // Upper wick must be significantly larger than body
   if(body == 0) return false;
   double wick_body_ratio = upper_wick / body;
   if(wick_body_ratio < Min_Wick_Body_Ratio) return false;
   
   // Lower wick should be small
   if(lower_wick > body * 0.5) return false;
   
   return true;
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
   double trend_ema[], atr[];
   ArraySetAsSeries(trend_ema, true);
   ArraySetAsSeries(atr, true);
   
   if(CopyBuffer(handle_trend_ema, 0, 0, 2, trend_ema) < 2) return;
   if(CopyBuffer(handle_atr, 0, 0, 2, atr) < 2) return;
   
   //--- Get price data
   double close_price = iClose(_Symbol, PERIOD_CURRENT, 1);
   double low_price = iLow(_Symbol, PERIOD_CURRENT, 1);
   double high_price = iHigh(_Symbol, PERIOD_CURRENT, 1);
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
   
   //--- Check for pin bars
   bool bullish_pin = IsBullishPinBar(1);
   bool bearish_pin = IsBearishPinBar(1);
   
   //--- Entry signals (pin bar against trend as reversal)
   bool buy_signal = bullish_pin && downtrend;   // Hammer in downtrend
   bool sell_signal = bearish_pin && uptrend;     // Shooting star in uptrend
   
   //--- Calculate lot size
   double lots = LotSize;
   if(UseRiskManagement)
   {
      double sl_points = current_atr * ATR_SL_Multiplier / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      lots = TradeManager.CalculateLotSize(_Symbol, RiskPercent, sl_points);
   }
   
   //--- Buy signal (bullish pin bar/hammer)
   if(buy_signal)
   {
      double sl = low_price - (current_atr * 0.5);  // SL below pin bar low
      double sl_distance = bid - sl;
      double tp = bid + (sl_distance * RR_Ratio);
      
      TradeManager.OpenBuy(_Symbol, lots, sl, tp, "PinBar_Buy");
      Print("BUY Signal: Bullish Pin Bar (Hammer) detected at ", DoubleToString(close_price, 5));
   }
   
   //--- Sell signal (bearish pin bar/shooting star)
   if(sell_signal)
   {
      double sl = high_price + (current_atr * 0.5);  // SL above pin bar high
      double sl_distance = sl - ask;
      double tp = ask - (sl_distance * RR_Ratio);
      
      TradeManager.OpenSell(_Symbol, lots, sl, tp, "PinBar_Sell");
      Print("SELL Signal: Bearish Pin Bar (Shooting Star) detected at ", DoubleToString(close_price, 5));
   }
}
//+------------------------------------------------------------------+