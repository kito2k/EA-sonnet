//+------------------------------------------------------------------+
//|                                                   TradeUtils.mqh |
//|                                    Shared trade management utils |
//|                                   Hedging-safe MT5 trade helpers |
//+------------------------------------------------------------------+
#property copyright "EA Sonnet"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Hedging-safe trade manager class                                 |
//+------------------------------------------------------------------+
class CTradeManager
{
private:
   CTrade            m_trade;
   string            m_magic_prefix;
   int               m_magic_number;
   double            m_lotsize;
   int               m_slippage;
   
public:
   CTradeManager(int magic, double lots = 0.01, int slippage = 30)
   {
      m_magic_number = magic;
      m_lotsize = lots;
      m_slippage = slippage;
      m_magic_prefix = "EA_" + IntegerToString(magic) + "_";
      
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(slippage);
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
      m_trade.SetAsyncMode(false);
   }
   
   //+------------------------------------------------------------------+
   //| Open a buy position with SL/TP                                   |
   //+------------------------------------------------------------------+
   bool OpenBuy(string symbol, double lots, double sl, double tp, string comment = "")
   {
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      
      if(sl > 0) sl = NormalizeDouble(sl, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
      if(tp > 0) tp = NormalizeDouble(tp, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
      
      string full_comment = m_magic_prefix + comment;
      
      if(m_trade.Buy(lots, symbol, ask, sl, tp, full_comment))
      {
         Print("BUY opened: ", symbol, " at ", ask, " SL:", sl, " TP:", tp);
         return true;
      }
      else
      {
         Print("BUY failed: ", m_trade.ResultRetcodeDescription());
         return false;
      }
   }
   
   //+------------------------------------------------------------------+
   //| Open a sell position with SL/TP                                  |
   //+------------------------------------------------------------------+
   bool OpenSell(string symbol, double lots, double sl, double tp, string comment = "")
   {
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      
      if(sl > 0) sl = NormalizeDouble(sl, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
      if(tp > 0) tp = NormalizeDouble(tp, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
      
      string full_comment = m_magic_prefix + comment;
      
      if(m_trade.Sell(lots, symbol, bid, sl, tp, full_comment))
      {
         Print("SELL opened: ", symbol, " at ", bid, " SL:", sl, " TP:", tp);
         return true;
      }
      else
      {
         Print("SELL failed: ", m_trade.ResultRetcodeDescription());
         return false;
      }
   }
   
   //+------------------------------------------------------------------+
   //| Close position by ticket (hedging-safe)                          |
   //+------------------------------------------------------------------+
   bool ClosePosition(ulong ticket)
   {
      if(PositionSelectByTicket(ticket))
      {
         if(m_trade.PositionClose(ticket))
         {
            Print("Position closed: ", ticket);
            return true;
         }
         else
         {
            Print("Close failed for ticket ", ticket, ": ", m_trade.ResultRetcodeDescription());
            return false;
         }
      }
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Close all positions for symbol with our magic                    |
   //+------------------------------------------------------------------+
   int CloseAllPositions(string symbol)
   {
      int closed = 0;
      
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0)
         {
            if(PositionGetString(POSITION_SYMBOL) == symbol && 
               PositionGetInteger(POSITION_MAGIC) == m_magic_number)
            {
               if(ClosePosition(ticket))
                  closed++;
            }
         }
      }
      
      return closed;
   }
   
   //+------------------------------------------------------------------+
   //| Close positions by type (BUY or SELL) for symbol                 |
   //+------------------------------------------------------------------+
   int ClosePositionsByType(string symbol, ENUM_POSITION_TYPE pos_type)
   {
      int closed = 0;
      
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0)
         {
            if(PositionGetString(POSITION_SYMBOL) == symbol && 
               PositionGetInteger(POSITION_MAGIC) == m_magic_number &&
               (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == pos_type)
            {
               if(ClosePosition(ticket))
                  closed++;
            }
         }
      }
      
      return closed;
   }
   
   //+------------------------------------------------------------------+
   //| Modify position SL/TP                                             |
   //+------------------------------------------------------------------+
   bool ModifyPosition(ulong ticket, double sl, double tp)
   {
      if(PositionSelectByTicket(ticket))
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         
         if(sl > 0) sl = NormalizeDouble(sl, digits);
         if(tp > 0) tp = NormalizeDouble(tp, digits);
         
         if(m_trade.PositionModify(ticket, sl, tp))
         {
            Print("Position modified: ", ticket, " SL:", sl, " TP:", tp);
            return true;
         }
         else
         {
            Print("Modify failed: ", m_trade.ResultRetcodeDescription());
            return false;
         }
      }
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Count open positions for symbol with our magic                   |
   //+------------------------------------------------------------------+
   int CountPositions(string symbol, ENUM_POSITION_TYPE pos_type = -1)
   {
      int count = 0;
      
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0)
         {
            if(PositionGetString(POSITION_SYMBOL) == symbol && 
               PositionGetInteger(POSITION_MAGIC) == m_magic_number)
            {
               if(pos_type == -1 || (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == pos_type)
                  count++;
            }
         }
      }
      
      return count;
   }
   
   //+------------------------------------------------------------------+
   //| Get all position tickets for symbol with our magic               |
   //+------------------------------------------------------------------+
   void GetPositionTickets(string symbol, ulong &tickets[])
   {
      ArrayResize(tickets, 0);
      
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0)
         {
            if(PositionGetString(POSITION_SYMBOL) == symbol && 
               PositionGetInteger(POSITION_MAGIC) == m_magic_number)
            {
               int size = ArraySize(tickets);
               ArrayResize(tickets, size + 1);
               tickets[size] = ticket;
            }
         }
      }
   }
   
   //+------------------------------------------------------------------+
   //| Calculate lot size based on risk percentage                      |
   //+------------------------------------------------------------------+
   double CalculateLotSize(string symbol, double risk_percent, double sl_points)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double risk_amount = balance * risk_percent / 100.0;
      
      double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      
      double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      
      double money_per_point = tick_value / tick_size * point;
      double lots = risk_amount / (sl_points * money_per_point);
      
      lots = MathFloor(lots / lot_step) * lot_step;
      
      if(lots < min_lot) lots = min_lot;
      if(lots > max_lot) lots = max_lot;
      
      return NormalizeDouble(lots, 2);
   }
};

//+------------------------------------------------------------------+
//| Helper functions                                                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Check if new bar formed                                           |
//+------------------------------------------------------------------+
bool IsNewBar(string symbol, ENUM_TIMEFRAMES timeframe, datetime &last_bar_time)
{
   datetime current_bar_time = iTime(symbol, timeframe, 0);
   
   if(last_bar_time == 0)
   {
      last_bar_time = current_bar_time;
      return false;
   }
   
   if(current_bar_time != last_bar_time)
   {
      last_bar_time = current_bar_time;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Normalize price to symbol digits                                 |
//+------------------------------------------------------------------+
double NormalizePrice(string symbol, double price)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

//+------------------------------------------------------------------+
//| Convert points to price distance                                 |
//+------------------------------------------------------------------+
double PointsToPrice(string symbol, double points)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   return points * point;
}

//+------------------------------------------------------------------+
//| Convert price distance to points                                 |
//+------------------------------------------------------------------+
double PriceToPoints(string symbol, double price_distance)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   return price_distance / point;
}