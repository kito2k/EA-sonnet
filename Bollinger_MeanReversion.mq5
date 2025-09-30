//+------------------------------------------------------------------+
//|                                      Bollinger_MeanReversion.mq5 |
//|                                                       EA Sonnet  |
//|         Mean Reversion: Buy at lower BB, Sell at upper BB       |
//|                      with RSI oversold/overbought filter         |
//+------------------------------------------------------------------+
#property copyright "EA Sonnet"
#property version   "1.00"
#property strict

#include "TradeUtils.mqh"

//--- Input parameters
input int      BB_Period = 20;                // Bollinger Bands Period
input double   BB_Deviation = 2.0;            // Bollinger Bands Deviation
input int      RSI_Period = 14;               // RSI Period
input double   RSI_Oversold = 30.0;           // RSI Oversold Level
input double   RSI_Overbought = 70.0;         // RSI Overbought Level
input double   TP_Percent = 50.0;             // TP % to Middle Band (0-100)
input bool     UseFixedSL = true;             // Use Fixed SL in Points
input int      FixedSL_Points = 200;          // Fixed SL Points
input double   LotSize = 0.01;                // Lot Size
input bool     UseRiskManagement = false;     // Use Risk Management
input double   RiskPercent = 1.0;             // Risk Percent (if enabled)
input int      MagicNumber = 10002;           // Magic Number
input bool     OneTradePerBar = true;         // One Trade Per Bar
input int      MaxPositions = 2;              // Max Concurrent Positions

//--- Global variables
CTradeManager *TradeManager;
int handle_bb;
int handle_rsi;
datetime last_trade_bar;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Create trade manager
   TradeManager = new CTradeManager(MagicNumber, LotSize);
   
   //--- Create indicators
   handle_bb = iBands(_Symbol, PERIOD_CURRENT, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
   handle_rsi = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   
   if(handle_bb == INVALID_HANDLE || handle_rsi == INVALID_HANDLE)
   {
      Print("Failed to create indicators");
      return INIT_FAILED;
   }
   
   last_trade_bar = 0;
   
   Print("Bollinger Mean Reversion EA initialized");
   Print("BB Period: ", BB_Period, " | Deviation: ", BB_Deviation);
   Print("RSI Period: ", RSI_Period, " | Oversold: ", RSI_Oversold, " | Overbought: ", RSI_Overbought);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicators
   if(handle_bb != INVALID_HANDLE) IndicatorRelease(handle_bb);
   if(handle_rsi != INVALID_HANDLE) IndicatorRelease(handle_rsi);
   
   //--- Delete trade manager
   if(TradeManager != NULL) delete TradeManager;
   
   Print("Bollinger Mean Reversion EA deinitialized");
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
   double bb_upper[], bb_middle[], bb_lower[], rsi[];
   ArraySetAsSeries(bb_upper, true);
   ArraySetAsSeries(bb_middle, true);
   ArraySetAsSeries(bb_lower, true);
   ArraySetAsSeries(rsi, true);
   
   if(CopyBuffer(handle_bb, 1, 0, 2, bb_upper) < 2) return;   // Upper band
   if(CopyBuffer(handle_bb, 0, 0, 2, bb_middle) < 2) return;  // Middle band
   if(CopyBuffer(handle_bb, 2, 0, 2, bb_lower) < 2) return;   // Lower band
   if(CopyBuffer(handle_rsi, 0, 0, 2, rsi) < 2) return;
   
   //--- Get current price
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double close_price = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   //--- Check for mean reversion signals
   bool buy_signal = (close_price <= bb_lower[1]) && (rsi[1] < RSI_Oversold);
   bool sell_signal = (close_price >= bb_upper[1]) && (rsi[1] > RSI_Overbought);
   
   //--- Calculate TP based on middle band
   double buy_tp = bb_middle[1];
   double sell_tp = bb_middle[1];
   
   // Adjust TP to percentage of way to middle
   if(TP_Percent < 100.0)
   {
      double buy_distance = bb_middle[1] - close_price;
      buy_tp = close_price + (buy_distance * TP_Percent / 100.0);
      
      double sell_distance = close_price - bb_middle[1];
      sell_tp = close_price - (sell_distance * TP_Percent / 100.0);
   }
   
   //--- Buy signal (oversold at lower band)
   if(buy_signal)
   {
      double sl = 0;
      if(UseFixedSL)
      {
         sl = bid - PointsToPrice(_Symbol, FixedSL_Points);
      }
      else
      {
         // SL below lower band
         double band_width = bb_upper[1] - bb_lower[1];
         sl = bb_lower[1] - (band_width * 0.1);
      }
      
      double lots = LotSize;
      if(UseRiskManagement)
      {
         double sl_points = (bid - sl) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         lots = TradeManager.CalculateLotSize(_Symbol, RiskPercent, sl_points);
      }
      
      TradeManager.OpenBuy(_Symbol, lots, sl, buy_tp, "BB_Mean_Buy");
      Print("BUY Signal: Price at lower BB, RSI oversold (", DoubleToString(rsi[1], 2), ")");
   }
   
   //--- Sell signal (overbought at upper band)
   if(sell_signal)
   {
      double sl = 0;
      if(UseFixedSL)
      {
         sl = ask + PointsToPrice(_Symbol, FixedSL_Points);
      }
      else
      {
         // SL above upper band
         double band_width = bb_upper[1] - bb_lower[1];
         sl = bb_upper[1] + (band_width * 0.1);
      }
      
      double lots = LotSize;
      if(UseRiskManagement)
      {
         double sl_points = (sl - ask) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         lots = TradeManager.CalculateLotSize(_Symbol, RiskPercent, sl_points);
      }
      
      TradeManager.OpenSell(_Symbol, lots, sl, sell_tp, "BB_Mean_Sell");
      Print("SELL Signal: Price at upper BB, RSI overbought (", DoubleToString(rsi[1], 2), ")");
   }
}
//+------------------------------------------------------------------+