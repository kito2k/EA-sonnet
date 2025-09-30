//+------------------------------------------------------------------+
//|                                   Ichimoku_Cloud_Breakout.mq5    |
//|                                                       EA Sonnet  |
//|      Ichimoku Cloud Breakout with Tenkan/Kijun Cross           |
//+------------------------------------------------------------------+
#property copyright "EA Sonnet"
#property version   "1.00"
#property strict

#include "TradeUtils.mqh"

//--- Input parameters
input int      Tenkan_Period = 9;             // Tenkan-sen Period
input int      Kijun_Period = 26;             // Kijun-sen Period
input int      Senkou_B_Period = 52;          // Senkou Span B Period
input int      ATR_Period = 14;               // ATR Period
input double   ATR_SL_Multiplier = 2.0;       // ATR Stop Loss Multiplier
input double   ATR_TP_Multiplier = 4.0;       // ATR Take Profit Multiplier
input double   LotSize = 0.01;                // Lot Size
input bool     UseRiskManagement = false;     // Use Risk Management
input double   RiskPercent = 1.0;             // Risk Percent (if enabled)
input int      MagicNumber = 10009;           // Magic Number
input bool     OneTradePerBar = true;         // One Trade Per Bar
input int      MaxPositions = 1;              // Max Concurrent Positions

//--- Global variables
CTradeManager *TradeManager;
int handle_ichimoku;
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
   handle_ichimoku = iIchimoku(_Symbol, PERIOD_CURRENT, Tenkan_Period, Kijun_Period, Senkou_B_Period);
   handle_atr = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   
   if(handle_ichimoku == INVALID_HANDLE || handle_atr == INVALID_HANDLE)
   {
      Print("Failed to create indicators");
      return INIT_FAILED;
   }
   
   last_trade_bar = 0;
   
   Print("Ichimoku Cloud Breakout EA initialized");
   Print("Ichimoku: ", Tenkan_Period, "/", Kijun_Period, "/", Senkou_B_Period);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicators
   if(handle_ichimoku != INVALID_HANDLE) IndicatorRelease(handle_ichimoku);
   if(handle_atr != INVALID_HANDLE) IndicatorRelease(handle_atr);
   
   //--- Delete trade manager
   if(TradeManager != NULL) delete TradeManager;
   
   Print("Ichimoku Cloud Breakout EA deinitialized");
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
   double tenkan[], kijun[], senkou_a[], senkou_b[], atr[];
   ArraySetAsSeries(tenkan, true);
   ArraySetAsSeries(kijun, true);
   ArraySetAsSeries(senkou_a, true);
   ArraySetAsSeries(senkou_b, true);
   ArraySetAsSeries(atr, true);
   
   if(CopyBuffer(handle_ichimoku, 0, 0, 3, tenkan) < 3) return;        // Tenkan-sen
   if(CopyBuffer(handle_ichimoku, 1, 0, 3, kijun) < 3) return;         // Kijun-sen
   if(CopyBuffer(handle_ichimoku, 2, 0, 27, senkou_a) < 27) return;    // Senkou Span A
   if(CopyBuffer(handle_ichimoku, 3, 0, 27, senkou_b) < 27) return;    // Senkou Span B
   if(CopyBuffer(handle_atr, 0, 0, 2, atr) < 2) return;
   
   //--- Get price data
   double close_current = iClose(_Symbol, PERIOD_CURRENT, 1);
   double close_prev = iClose(_Symbol, PERIOD_CURRENT, 2);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double current_atr = atr[1];
   
   //--- Cloud calculation (shifted 26 periods into future, so we use index 26)
   double cloud_top = MathMax(senkou_a[26], senkou_b[26]);
   double cloud_bottom = MathMin(senkou_a[26], senkou_b[26]);
   
   //--- Tenkan/Kijun cross
   bool tk_cross_bullish = (tenkan[1] > kijun[1]) && (tenkan[2] <= kijun[2]);
   bool tk_cross_bearish = (tenkan[1] < kijun[1]) && (tenkan[2] >= kijun[2]);
   
   //--- Price vs Cloud
   bool price_above_cloud = close_current > cloud_top;
   bool price_below_cloud = close_current < cloud_bottom;
   
   //--- Strong bullish: TK cross + price above cloud
   bool buy_signal = tk_cross_bullish && price_above_cloud;
   
   //--- Strong bearish: TK cross + price below cloud
   bool sell_signal = tk_cross_bearish && price_below_cloud;
   
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
      
      TradeManager.OpenBuy(_Symbol, lots, sl, tp, "Ichimoku_Buy");
      Print("BUY Signal: TK cross + price above cloud");
   }
   
   //--- Sell signal
   if(sell_signal)
   {
      double sl = ask + (current_atr * ATR_SL_Multiplier);
      double tp = ask - (current_atr * ATR_TP_Multiplier);
      
      TradeManager.OpenSell(_Symbol, lots, sl, tp, "Ichimoku_Sell");
      Print("SELL Signal: TK cross + price below cloud");
   }
}
//+------------------------------------------------------------------+