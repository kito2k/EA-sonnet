//+------------------------------------------------------------------+
//|                                        RSI_Pullback_Trend.mq5    |
//|                                                       EA Sonnet  |
//|    Trend Following with 200 EMA + RSI Pullback Entry Timing     |
//+------------------------------------------------------------------+
#property copyright "EA Sonnet"
#property version   "1.00"
#property strict

#include "TradeUtils.mqh"

//--- Input parameters
input int      Trend_EMA_Period = 200;        // Trend EMA Period
input int      RSI_Period = 14;               // RSI Period
input double   RSI_Buy_Max = 40.0;            // RSI Buy Entry Max (pullback)
input double   RSI_Sell_Min = 60.0;           // RSI Sell Entry Min (pullback)
input int      ATR_Period = 14;               // ATR Period
input double   ATR_SL_Multiplier = 2.0;       // ATR Stop Loss Multiplier
input double   ATR_TP_Multiplier = 4.0;       // ATR Take Profit Multiplier
input double   LotSize = 0.01;                // Lot Size
input bool     UseRiskManagement = false;     // Use Risk Management
input double   RiskPercent = 1.0;             // Risk Percent (if enabled)
input int      MagicNumber = 10005;           // Magic Number
input bool     OneTradePerBar = true;         // One Trade Per Bar
input int      MaxPositions = 1;              // Max Concurrent Positions
input bool     CloseOnOpposite = true;        // Close on Opposite Trend

//--- Global variables
CTradeManager *TradeManager;
int handle_trend_ema;
int handle_rsi;
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
   handle_rsi = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   handle_atr = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   
   if(handle_trend_ema == INVALID_HANDLE || handle_rsi == INVALID_HANDLE || handle_atr == INVALID_HANDLE)
   {
      Print("Failed to create indicators");
      return INIT_FAILED;
   }
   
   last_trade_bar = 0;
   
   Print("RSI Pullback Trend EA initialized");
   Print("Trend EMA: ", Trend_EMA_Period);
   Print("RSI Period: ", RSI_Period, " | Buy Max: ", RSI_Buy_Max, " | Sell Min: ", RSI_Sell_Min);
   Print("ATR SL: ", ATR_SL_Multiplier, " | ATR TP: ", ATR_TP_Multiplier);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicators
   if(handle_trend_ema != INVALID_HANDLE) IndicatorRelease(handle_trend_ema);
   if(handle_rsi != INVALID_HANDLE) IndicatorRelease(handle_rsi);
   if(handle_atr != INVALID_HANDLE) IndicatorRelease(handle_atr);
   
   //--- Delete trade manager
   if(TradeManager != NULL) delete TradeManager;
   
   Print("RSI Pullback Trend EA deinitialized");
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
   double trend_ema[], rsi[], atr[];
   ArraySetAsSeries(trend_ema, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(atr, true);
   
   if(CopyBuffer(handle_trend_ema, 0, 0, 3, trend_ema) < 3) return;
   if(CopyBuffer(handle_rsi, 0, 0, 3, rsi) < 3) return;
   if(CopyBuffer(handle_atr, 0, 0, 2, atr) < 2) return;
   
   //--- Get price data
   double close_current = iClose(_Symbol, PERIOD_CURRENT, 1);
   double close_prev = iClose(_Symbol, PERIOD_CURRENT, 2);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double current_atr = atr[1];
   
   //--- Determine trend direction
   bool uptrend = close_current > trend_ema[1];
   bool downtrend = close_current < trend_ema[1];
   
   //--- Check for pullback entry conditions
   // In uptrend: RSI pulled back (below threshold) and now starting to rise
   bool buy_signal = uptrend && 
                     (rsi[1] <= RSI_Buy_Max) && 
                     (rsi[1] > rsi[2]);  // RSI turning up
   
   // In downtrend: RSI pulled back (above threshold) and now starting to fall
   bool sell_signal = downtrend && 
                      (rsi[1] >= RSI_Sell_Min) && 
                      (rsi[1] < rsi[2]);  // RSI turning down
   
   //--- Close opposite positions if enabled
   if(CloseOnOpposite)
   {
      if(uptrend && TradeManager.CountPositions(_Symbol, POSITION_TYPE_SELL) > 0)
      {
         TradeManager.ClosePositionsByType(_Symbol, POSITION_TYPE_SELL);
         Print("Closed SELL positions - trend changed to UP");
      }
      
      if(downtrend && TradeManager.CountPositions(_Symbol, POSITION_TYPE_BUY) > 0)
      {
         TradeManager.ClosePositionsByType(_Symbol, POSITION_TYPE_BUY);
         Print("Closed BUY positions - trend changed to DOWN");
      }
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
   
   //--- Buy signal (uptrend pullback)
   if(buy_signal)
   {
      double sl = bid - (current_atr * ATR_SL_Multiplier);
      double tp = bid + (current_atr * ATR_TP_Multiplier);
      
      TradeManager.OpenBuy(_Symbol, lots, sl, tp, "RSI_PB_Buy");
      Print("BUY Signal: Uptrend pullback, RSI=", DoubleToString(rsi[1], 2), 
            " Price above EMA(", Trend_EMA_Period, ")");
   }
   
   //--- Sell signal (downtrend pullback)
   if(sell_signal)
   {
      double sl = ask + (current_atr * ATR_SL_Multiplier);
      double tp = ask - (current_atr * ATR_TP_Multiplier);
      
      TradeManager.OpenSell(_Symbol, lots, sl, tp, "RSI_PB_Sell");
      Print("SELL Signal: Downtrend pullback, RSI=", DoubleToString(rsi[1], 2),
            " Price below EMA(", Trend_EMA_Period, ")");
   }
}
//+------------------------------------------------------------------+