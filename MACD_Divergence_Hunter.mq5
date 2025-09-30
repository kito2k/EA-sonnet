//+------------------------------------------------------------------+
//|                                    MACD_Divergence_Hunter.mq5    |
//|                                                       EA Sonnet  |
//|         MACD Histogram Divergence Detection for Reversals       |
//+------------------------------------------------------------------+
#property copyright "EA Sonnet"
#property version   "1.00"
#property strict

#include "TradeUtils.mqh"

//--- Input parameters
input int      MACD_Fast = 12;                // MACD Fast EMA
input int      MACD_Slow = 26;                // MACD Slow EMA
input int      MACD_Signal = 9;               // MACD Signal
input int      Divergence_Lookback = 10;      // Bars to Look for Divergence
input double   Min_Divergence_Pips = 10.0;    // Minimum Divergence Size (pips)
input int      ATR_Period = 14;               // ATR Period
input double   ATR_SL_Multiplier = 2.5;       // ATR Stop Loss Multiplier
input double   ATR_TP_Multiplier = 3.5;       // ATR Take Profit Multiplier
input double   LotSize = 0.01;                // Lot Size
input bool     UseRiskManagement = false;     // Use Risk Management
input double   RiskPercent = 1.0;             // Risk Percent (if enabled)
input int      MagicNumber = 10006;           // Magic Number
input bool     OneTradePerBar = true;         // One Trade Per Bar
input int      MaxPositions = 1;              // Max Concurrent Positions

//--- Global variables
CTradeManager *TradeManager;
int handle_macd;
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
   handle_macd = iMACD(_Symbol, PERIOD_CURRENT, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   handle_atr = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   
   if(handle_macd == INVALID_HANDLE || handle_atr == INVALID_HANDLE)
   {
      Print("Failed to create indicators");
      return INIT_FAILED;
   }
   
   last_trade_bar = 0;
   
   Print("MACD Divergence Hunter EA initialized");
   Print("MACD: ", MACD_Fast, "/", MACD_Slow, "/", MACD_Signal);
   Print("Divergence Lookback: ", Divergence_Lookback, " bars");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicators
   if(handle_macd != INVALID_HANDLE) IndicatorRelease(handle_macd);
   if(handle_atr != INVALID_HANDLE) IndicatorRelease(handle_atr);
   
   //--- Delete trade manager
   if(TradeManager != NULL) delete TradeManager;
   
   Print("MACD Divergence Hunter EA deinitialized");
}

//+------------------------------------------------------------------+
//| Find price low within lookback period                            |
//+------------------------------------------------------------------+
int FindLowestBar(int lookback)
{
   int lowest_bar = 1;
   double lowest_price = iLow(_Symbol, PERIOD_CURRENT, 1);
   
   for(int i = 2; i <= lookback; i++)
   {
      double price = iLow(_Symbol, PERIOD_CURRENT, i);
      if(price < lowest_price)
      {
         lowest_price = price;
         lowest_bar = i;
      }
   }
   
   return lowest_bar;
}

//+------------------------------------------------------------------+
//| Find price high within lookback period                           |
//+------------------------------------------------------------------+
int FindHighestBar(int lookback)
{
   int highest_bar = 1;
   double highest_price = iHigh(_Symbol, PERIOD_CURRENT, 1);
   
   for(int i = 2; i <= lookback; i++)
   {
      double price = iHigh(_Symbol, PERIOD_CURRENT, i);
      if(price > highest_price)
      {
         highest_price = price;
         highest_bar = i;
      }
   }
   
   return highest_bar;
}

//+------------------------------------------------------------------+
//| Check for bullish divergence (price lower low, MACD higher low) |
//+------------------------------------------------------------------+
bool CheckBullishDivergence(const double &macd_histogram[])
{
   int price_low_bar = FindLowestBar(Divergence_Lookback);
   
   if(price_low_bar < 2) return false;
   
   // Current price low
   double current_price_low = iLow(_Symbol, PERIOD_CURRENT, 1);
   double previous_price_low = iLow(_Symbol, PERIOD_CURRENT, price_low_bar);
   
   // Check if price made lower low
   if(current_price_low >= previous_price_low) return false;
   
   // MACD histogram values
   double current_macd = macd_histogram[1];
   double previous_macd = macd_histogram[price_low_bar];
   
   // Check if MACD made higher low (divergence)
   if(current_macd > previous_macd)
   {
      double price_diff = (previous_price_low - current_price_low) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      if(price_diff >= Min_Divergence_Pips)
      {
         Print("Bullish Divergence detected: Price LL, MACD HL");
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for bearish divergence (price higher high, MACD lower high)|
//+------------------------------------------------------------------+
bool CheckBearishDivergence(const double &macd_histogram[])
{
   int price_high_bar = FindHighestBar(Divergence_Lookback);
   
   if(price_high_bar < 2) return false;
   
   // Current price high
   double current_price_high = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double previous_price_high = iHigh(_Symbol, PERIOD_CURRENT, price_high_bar);
   
   // Check if price made higher high
   if(current_price_high <= previous_price_high) return false;
   
   // MACD histogram values
   double current_macd = macd_histogram[1];
   double previous_macd = macd_histogram[price_high_bar];
   
   // Check if MACD made lower high (divergence)
   if(current_macd < previous_macd)
   {
      double price_diff = (current_price_high - previous_price_high) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      if(price_diff >= Min_Divergence_Pips)
      {
         Print("Bearish Divergence detected: Price HH, MACD LH");
         return true;
      }
   }
   
   return false;
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
   double macd_main[], macd_signal[], macd_histogram[], atr[];
   ArraySetAsSeries(macd_main, true);
   ArraySetAsSeries(macd_signal, true);
   ArraySetAsSeries(macd_histogram, true);
   ArraySetAsSeries(atr, true);
   
   int lookback_size = Divergence_Lookback + 5;
   if(CopyBuffer(handle_macd, 0, 0, lookback_size, macd_main) < lookback_size) return;
   if(CopyBuffer(handle_macd, 1, 0, lookback_size, macd_signal) < lookback_size) return;
   
   // Calculate histogram manually
   ArrayResize(macd_histogram, lookback_size);
   for(int i = 0; i < lookback_size; i++)
      macd_histogram[i] = macd_main[i] - macd_signal[i];
   
   if(CopyBuffer(handle_atr, 0, 0, 2, atr) < 2) return;
   
   //--- Check for divergences
   bool bullish_div = CheckBullishDivergence(macd_histogram);
   bool bearish_div = CheckBearishDivergence(macd_histogram);
   
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
   
   //--- Buy signal (bullish divergence)
   if(bullish_div)
   {
      double sl = bid - (current_atr * ATR_SL_Multiplier);
      double tp = bid + (current_atr * ATR_TP_Multiplier);
      
      TradeManager.OpenBuy(_Symbol, lots, sl, tp, "MACD_Div_Buy");
      Print("BUY Signal: Bullish MACD divergence detected");
   }
   
   //--- Sell signal (bearish divergence)
   if(bearish_div)
   {
      double sl = ask + (current_atr * ATR_SL_Multiplier);
      double tp = ask - (current_atr * ATR_TP_Multiplier);
      
      TradeManager.OpenSell(_Symbol, lots, sl, tp, "MACD_Div_Sell");
      Print("SELL Signal: Bearish MACD divergence detected");
   }
}
//+------------------------------------------------------------------+