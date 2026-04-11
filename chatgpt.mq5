//+------------------------------------------------------------------+
//|        XAUUSD_AI_ELITE_FTMO.mq5                                 |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

//================ INPUTS =================
input bool AutoMode = true;
input int StrategyMode = 0;

input double RiskPerTrade = 1.0;
input int MaxTrades = 3;

input double DailyLossLimit = 5.0;   // %
input double MaxDrawdown = 10.0;     // %

input bool UseSessions = true;
input bool UseNewsFilter = true;

input int NewsBufferMinutes = 30;
input string NewsTimes = "14:30;16:00"; // manually update daily

input int Magic = 777777;

//================ GLOBALS =================
double DayStartEquity;
double PeakEquity;
double ATR_Value;

//================ TIME =================
bool IsSessionTime()
{
   if(!UseSessions) return true;

   datetime t = TimeCurrent();
   int hour = TimeHour(t);

   // London + NY
   if((hour >= 7 && hour <= 10) || (hour >= 13 && hour <= 16))
      return true;

   return false;
}

//================ NEWS FILTER =================
bool IsNewsTime()
{
   if(!UseNewsFilter) return false;

   datetime now = TimeCurrent();

   string times[];
   int count = StringSplit(NewsTimes, ';', times);

   for(int i=0;i<count;i++)
   {
      datetime news = StringToTime(TimeToString(now, TIME_DATE) + " " + times[i]);

      if(MathAbs((int)(now - news)) <= NewsBufferMinutes*60)
         return true;
   }

   return false;
}

//================ ATR =================
double GetATR()
{
   return iATR(_Symbol, PERIOD_M1, 14, 0);
}

//================ LOT =================
double GetLot(double sl)
{
   double risk = AccountInfoDouble(ACCOUNT_EQUITY) * RiskPerTrade / 100.0;

   // Risk reduction after profit
   double profit = AccountInfoDouble(ACCOUNT_EQUITY) - DayStartEquity;

   if(profit >= 3) risk *= 0.5;
   if(profit >= 5) risk *= 0.3;

   double lot = risk / (sl * _Point * 10);
   return NormalizeDouble(lot, 2);
}

//================ SPREAD =================
bool SpreadOK()
{
   int spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   static int lastSpread = spread;

   if(spread > 300) return false;

   // spike filter
   if(spread > lastSpread * 1.5)
      return false;

   lastSpread = spread;
   return true;
}

//================ FTMO PROTECTION =================
bool CheckFTMO()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   double dailyLoss = (DayStartEquity - equity) / DayStartEquity * 100;
   double totalDD = (PeakEquity - equity) / PeakEquity * 100;

   if(equity > PeakEquity)
      PeakEquity = equity;

   if(dailyLoss >= DailyLossLimit)
      return false;

   if(totalDD >= MaxDrawdown)
      return false;

   return true;
}

//================ STRUCTURE =================
bool BOS(bool buy)
{
   double high = iHigh(_Symbol, PERIOD_M1, 5);
   double low  = iLow(_Symbol, PERIOD_M1, 5);

   if(buy && Close[0] > high) return true;
   if(!buy && Close[0] < low) return true;

   return false;
}

//================ LIQUIDITY =================
bool SweepHigh()
{
   return High[0] > iHigh(_Symbol, PERIOD_M1, 3);
}

bool SweepLow()
{
   return Low[0] < iLow(_Symbol, PERIOD_M1, 3);
}

//================ FVG =================
bool FVG_Buy() { return Low[0] > High[2]; }
bool FVG_Sell(){ return High[0] < Low[2]; }

//================ SCORE =================
double Score(bool buy)
{
   double s1 = BOS(buy) ? 1 : 0.3;
   double s2 = (buy ? SweepLow() : SweepHigh()) ? 1 : 0.3;
   double s3 = (buy ? FVG_Buy() : FVG_Sell()) ? 1 : 0.3;
   double s4 = ATR_Value > 150 ? 1 : 0.5;

   return s1*0.3 + s2*0.3 + s3*0.2 + s4*0.2;
}

//================ TRADE MGMT =================
void Manage()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetSymbol(i)!=_Symbol) continue;

      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      double risk = MathAbs(open - sl);
      double profit = MathAbs(price - open);

      // BE
      if(profit >= risk)
         trade.PositionModify(_Symbol, open, tp);

      // trailing
      double newSL = price - ATR_Value;
      if(newSL > sl)
         trade.PositionModify(_Symbol, newSL, tp);
   }
}

//================ MODES =================
void Execute(bool buy)
{
   double sl = ATR_Value * 1.5;
   double tp = sl * 2.5;

   double lot = GetLot(sl);

   if(buy)
      trade.Buy(lot,_Symbol,Ask,Ask-sl,Ask+tp);
   else
      trade.Sell(lot,_Symbol,Bid,Bid+sl,Bid-tp);
}

//================ MAIN =================
void OnTick()
{
   if(!IsSessionTime()) return;
   if(IsNewsTime()) return;
   if(!SpreadOK()) return;
   if(!CheckFTMO()) return;

   if(PositionsTotal() >= MaxTrades) return;

   ATR_Value = GetATR();

   double buyScore = Score(true);
   double sellScore = Score(false);

   if(buyScore < 0.7 && sellScore < 0.7) return;

   if(buyScore > sellScore)
      Execute(true);
   else
      Execute(false);

   Manage();

   Print("Buy:",buyScore," Sell:",sellScore," ATR:",ATR_Value);
}

//================ INIT =================
int OnInit()
{
   DayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   PeakEquity = DayStartEquity;
   return INIT_SUCCEEDED;
}