//+------------------------------------------------------------------+
//|                                      SmartMoney_ProEA_v7.mq5     |
//|            DEEP ANALYSIS — Weighted Scoring — Clean Chart          |
//|            Adjustable Timeframe — Based on v2 (best results)       |
//|            Toggle each analysis on/off in settings                 |
//|            Built for $50-$100 accounts                             |
//+------------------------------------------------------------------+
#property copyright "SmartMoney Pro v7.0"
#property version   "7.00"
#property strict
#property description "Deep analysis + weighted scoring"
#property description "Adjustable TF | Clean chart | Toggle layers"
#property description "Based on v2 logic — capital preservation"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                             |
//+------------------------------------------------------------------+
enum ENUM_ENTRY_TF
{
   TF_M5   = 0,   // M5
   TF_M15  = 1,   // M15 (recommended)
   TF_M30  = 2,   // M30
   TF_H1   = 3    // H1
};

enum ENUM_HTF
{
   HTF_H1  = 0,   // H1
   HTF_H4  = 1,   // H4 (recommended)
   HTF_D1  = 2    // D1
};

enum ENUM_RISK
{
   RISK_SAFE       = 0,   // Safe (0.5%)
   RISK_NORMAL     = 1,   // Normal (1%)
   RISK_MODERATE   = 2,   // Moderate (1.5%)
   RISK_AGGRESSIVE = 3    // Aggressive (2%)
};

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "═══════ TIMEFRAME ═══════"
input ENUM_ENTRY_TF  InpEntryTF     = TF_M15;       // Entry Timeframe
input ENUM_HTF       InpHTF         = HTF_H4;        // Trend Timeframe
input int            InpHistoryDays = 3;             // History Analysis (days)

input group "═══════ RISK MANAGEMENT ═══════"
input ENUM_RISK      InpRisk        = RISK_NORMAL;   // Risk Mode
input double         InpMaxLot      = 0.05;          // Max Lot
input int            InpMaxTrades   = 2;             // Max Open Trades
input double         InpMaxDD       = 15.0;          // Max Drawdown %
input double         InpBaseRR      = 2.5;           // Risk:Reward Ratio
input double         InpATR_SL      = 1.8;           // ATR multiplier for SL
input int            InpMagic       = 707070;        // Magic Number

input group "═══════ SCORING (weights 0-10) ═══════"
input int            InpW_Trend     = 10;    // Weight: HTF Trend Alignment
input int            InpW_Structure = 8;     // Weight: Market Structure (BOS)
input int            InpW_OB        = 7;     // Weight: Order Block
input int            InpW_FVG       = 5;     // Weight: Fair Value Gap
input int            InpW_Fib       = 7;     // Weight: Fibonacci OTE
input int            InpW_SNR       = 6;     // Weight: Support/Resistance
input int            InpW_Liq       = 4;     // Weight: Liquidity Sweep
input int            InpW_EMA       = 5;     // Weight: EMA Cross
input int            InpW_RSI       = 4;     // Weight: RSI Confirm
input int            InpW_MACD      = 3;     // Weight: MACD Confirm
input int            InpW_Stoch     = 3;     // Weight: Stochastic Confirm
input int            InpW_Engulf    = 6;     // Weight: Engulfing/PinBar
input int            InpW_Volume    = 3;     // Weight: Volume Confirm
input int            InpMinScore    = 25;    // Minimum Score to Enter

input group "═══════ BREAKEVEN (3-layer) ═══════"
input bool           InpUseBE       = true;
input int            InpBE1_At      = 15;    // Layer 1: trigger (pts)
input int            InpBE1_Lock    = 3;     // Layer 1: lock (pts)
input int            InpBE2_At      = 30;    // Layer 2: trigger (pts)
input int            InpBE2_Lock    = 15;    // Layer 2: lock (pts)
input int            InpBE3_At      = 50;    // Layer 3: trigger (pts)
input int            InpBE3_Lock    = 35;    // Layer 3: lock (pts)

input group "═══════ TRAILING STOP ═══════"
input bool           InpTrail       = true;
input int            InpTrailStart  = 40;    // Trail start (pts)
input int            InpTrailStep   = 18;    // Trail step (pts)

input group "═══════ TIME CLOSE ═══════"
input bool           InpTimeClose   = true;
input int            InpTC_Min      = 20;    // Close after N min in profit
input double         InpTC_MinProf  = 0.25;  // Min profit to time-close ($)

input group "═══════ SESSION ═══════"
input int            InpSessStart   = 7;     // Session start (GMT)
input int            InpSessEnd     = 20;    // Session end (GMT)
input bool           InpAvoidFri    = true;
input int            InpFriCut      = 17;

input group "═══════ NEWS ═══════"
input bool           InpNews        = true;
input int            InpNewsBefore  = 30;
input int            InpNewsAfter   = 15;

input group "═══════ ANALYSIS SETTINGS ═══════"
input int            InpOB_Lookback = 500;   // OB lookback (M1 bars)
input int            InpFVG_MinGap  = 8;     // FVG min gap (pts)
input int            InpSNR_Zone    = 12;    // SNR zone (pts)
input int            InpSNR_Touch   = 2;     // SNR min touches
input int            InpFib_Zone    = 10;    // Fib zone (pts)
input int            InpEMA_Fast    = 9;
input int            InpEMA_Slow    = 21;
input int            InpEMA_Trend   = 200;
input int            InpRSI_Per     = 14;
input int            InpATR_Per     = 14;

input group "═══════ CHART DISPLAY (toggle) ═══════"
input bool           InpShowOB      = true;  // Show Order Blocks
input bool           InpShowFVG     = true;  // Show Fair Value Gaps
input bool           InpShowSNR     = true;  // Show S/R Levels
input bool           InpShowFib     = true;  // Show Fibonacci
input bool           InpShowLiq     = false; // Show Liquidity Levels
input bool           InpShowAsian   = false; // Show Asian Range
input bool           InpShowSwings  = false; // Show Swing Points
input bool           InpShowPanel   = true;  // Show Info Panel
input bool           InpShowScore   = true;  // Show Score Breakdown

input group "═══════ COLORS ═══════"
input color          InpClrBullOB   = C'30,100,180';
input color          InpClrBearOB   = C'180,60,40';
input color          InpClrBullFVG  = C'40,160,60';
input color          InpClrBearFVG  = C'160,40,40';
input color          InpClrSup      = clrGold;
input color          InpClrRes      = clrMagenta;
input color          InpClrFib      = clrCyan;
input color          InpClrLiq      = clrDeepPink;

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
CTrade tr; CPositionInfo pi; CSymbolInfo si; CAccountInfo ai;

ENUM_TIMEFRAMES entryTF, htfTF;

// Entry TF handles
int hF,hS,hT,hRSI,hATR,hStoch,hMACD;
// HTF handles
int hHF,hHS,hH200;
// M1 for deep analysis
int hM1_ATR;

// Buffers
double bF[],bS[],bT[],bRSI[],bATR[];
double bSK[],bSD[],bMM[],bMS[];
double bHF[],bHS[],bH200[];
double bM1A[];

// Structures
struct SOB  { double hi,lo; datetime t; int d; double str; };
struct SFVG { double hi,lo; datetime t; int d; };
struct SSNR { double p; int tc,tp; };
struct SLIQ { double p; datetime t; int d; };
struct SSW  { double p; datetime t; int d; int b; };

SOB OBs[];  SFVG FVGs[];  SSNR SNRs[];  SLIQ LIQs[];  SSW SWs[];

// State
double peakBal, initBal;
datetime lastBar;
int trendEntry, trendHTF;
double asianHi, asianLo;
string PFX;

// Score breakdown (for display)
int sc_Trend,sc_Struct,sc_OB,sc_FVG,sc_Fib,sc_SNR,sc_Liq;
int sc_EMA,sc_RSI,sc_MACD,sc_Stoch,sc_Engulf,sc_Vol;
int lastBullScore, lastBearScore;

//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetEntryTF()
{
   switch(InpEntryTF)
   {
      case TF_M5:  return PERIOD_M5;
      case TF_M15: return PERIOD_M15;
      case TF_M30: return PERIOD_M30;
      case TF_H1:  return PERIOD_H1;
   }
   return PERIOD_M15;
}

ENUM_TIMEFRAMES GetHTF()
{
   switch(InpHTF)
   {
      case HTF_H1: return PERIOD_H1;
      case HTF_H4: return PERIOD_H4;
      case HTF_D1: return PERIOD_D1;
   }
   return PERIOD_H4;
}

double GetRiskPct()
{
   switch(InpRisk)
   {
      case RISK_SAFE:       return 0.5;
      case RISK_NORMAL:     return 1.0;
      case RISK_MODERATE:   return 1.5;
      case RISK_AGGRESSIVE: return 2.0;
   }
   return 1.0;
}

//+------------------------------------------------------------------+
//| INIT                                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   tr.SetExpertMagicNumber(InpMagic);
   tr.SetDeviationInPoints(15);
   tr.SetTypeFilling(ORDER_FILLING_FOK);
   if(!si.Name(_Symbol)) return INIT_FAILED;
   si.Refresh();
   
   entryTF = GetEntryTF();
   htfTF   = GetHTF();
   PFX     = "SM7_";
   
   // Entry TF indicators
   hF     = iMA(_Symbol, entryTF, InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   hS     = iMA(_Symbol, entryTF, InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   hT     = iMA(_Symbol, entryTF, InpEMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
   hRSI   = iRSI(_Symbol, entryTF, InpRSI_Per, PRICE_CLOSE);
   hATR   = iATR(_Symbol, entryTF, InpATR_Per);
   hStoch = iStochastic(_Symbol, entryTF, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
   hMACD  = iMACD(_Symbol, entryTF, 12, 26, 9, PRICE_CLOSE);
   
   // HTF trend
   hHF   = iMA(_Symbol, htfTF, InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   hHS   = iMA(_Symbol, htfTF, InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   hH200 = iMA(_Symbol, htfTF, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   // M1 ATR for news detection
   hM1_ATR = iATR(_Symbol, PERIOD_M1, 14);
   
   if(hF<0||hS<0||hT<0||hRSI<0||hATR<0||hStoch<0||hMACD<0||
      hHF<0||hHS<0||hH200<0||hM1_ATR<0)
   { Print("ERROR: handles"); return INIT_FAILED; }
   
   ArraySetAsSeries(bF,true);   ArraySetAsSeries(bS,true);   ArraySetAsSeries(bT,true);
   ArraySetAsSeries(bRSI,true); ArraySetAsSeries(bATR,true);
   ArraySetAsSeries(bSK,true);  ArraySetAsSeries(bSD,true);
   ArraySetAsSeries(bMM,true);  ArraySetAsSeries(bMS,true);
   ArraySetAsSeries(bHF,true);  ArraySetAsSeries(bHS,true);  ArraySetAsSeries(bH200,true);
   ArraySetAsSeries(bM1A,true);
   
   initBal = ai.Balance(); peakBal = initBal; lastBar = 0;
   trendEntry = 0; trendHTF = 0;
   lastBullScore = 0; lastBearScore = 0;
   
   EventSetTimer(1);
   
   Print("╔═══════════════════════════════════════════════╗");
   Print("║ SmartMoney Pro v7.0 — DEEP ANALYSIS");
   Print("║ Entry: ", EnumToString(entryTF), " | Trend: ", EnumToString(htfTF));
   Print("║ Balance: $", DoubleToString(initBal,2));
   Print("║ Risk: ", DoubleToString(GetRiskPct(),1), "% | Min Score: ", InpMinScore);
   Print("║ Max weight possible: ",
         InpW_Trend+InpW_Structure+InpW_OB+InpW_FVG+InpW_Fib+
         InpW_SNR+InpW_Liq+InpW_EMA+InpW_RSI+InpW_MACD+
         InpW_Stoch+InpW_Engulf+InpW_Volume);
   Print("╚═══════════════════════════════════════════════╝");
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int r)
{
   EventKillTimer();
   ObjectsDeleteAll(0, PFX);
   IndicatorRelease(hF);IndicatorRelease(hS);IndicatorRelease(hT);
   IndicatorRelease(hRSI);IndicatorRelease(hATR);IndicatorRelease(hStoch);
   IndicatorRelease(hMACD);
   IndicatorRelease(hHF);IndicatorRelease(hHS);IndicatorRelease(hH200);
   IndicatorRelease(hM1_ATR);
   Comment("");
}

//+------------------------------------------------------------------+
//| ON TICK                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   ManagePositions(); // every tick
   
   datetime cb = iTime(_Symbol, entryTF, 0);
   if(cb == lastBar) return;
   lastBar = cb;
   
   si.Refresh(); si.RefreshRates();
   if(CheckDD()) return;
   double b = ai.Balance(); if(b > peakBal) peakBal = b;
   if(!CopyBufs()) return;
   
   // Deep analysis
   CalcHTFTrend();
   CalcStructure();
   DetectSwings();
   DetectOBs();
   DetectFVGs();
   DetectSNRs();
   DetectLIQs();
   CalcAsian();
   
   DrawChart();
   
   if(!SessOK() || !FriOK()) return;
   if(InpNews && IsNews()) return;
   if(CntPos() >= InpMaxTrades) return;
   
   int sig = ScoreAndDecide();
   if(sig != 0) OpenTrade(sig);
}

bool CopyBufs()
{
   int n = 300;
   if(CopyBuffer(hF,0,0,n,bF)<=0) return false;
   if(CopyBuffer(hS,0,0,n,bS)<=0) return false;
   if(CopyBuffer(hT,0,0,n,bT)<=0) return false;
   if(CopyBuffer(hRSI,0,0,n,bRSI)<=0) return false;
   if(CopyBuffer(hATR,0,0,n,bATR)<=0) return false;
   if(CopyBuffer(hStoch,0,0,50,bSK)<=0) return false;
   if(CopyBuffer(hStoch,1,0,50,bSD)<=0) return false;
   if(CopyBuffer(hMACD,0,0,50,bMM)<=0) return false;
   if(CopyBuffer(hMACD,1,0,50,bMS)<=0) return false;
   if(CopyBuffer(hHF,0,0,30,bHF)<=0) return false;
   if(CopyBuffer(hHS,0,0,30,bHS)<=0) return false;
   if(CopyBuffer(hH200,0,0,30,bH200)<=0) return false;
   if(CopyBuffer(hM1_ATR,0,0,20,bM1A)<=0) return false;
   return true;
}

//+------------------------------------------------------------------+
//| HTF TREND                                                         |
//+------------------------------------------------------------------+
void CalcHTFTrend()
{
   // All 3 EMAs aligned = strong trend
   bool bull = bHF[0]>bHS[0] && bHF[0]>bH200[0] && bHS[0]>bH200[0];
   bool bear = bHF[0]<bHS[0] && bHF[0]<bH200[0] && bHS[0]<bH200[0];
   if(bull) trendHTF=1; else if(bear) trendHTF=-1; else trendHTF=0;
}

//+------------------------------------------------------------------+
//| ENTRY TF STRUCTURE                                                |
//+------------------------------------------------------------------+
void CalcStructure()
{
   double H[],L[],C[];
   ArraySetAsSeries(H,true); ArraySetAsSeries(L,true); ArraySetAsSeries(C,true);
   CopyHigh(_Symbol,entryTF,0,200,H);
   CopyLow(_Symbol,entryTF,0,200,L);
   CopyClose(_Symbol,entryTF,0,200,C);
   
   double sH1=0,sH2=0,sL1=DBL_MAX,sL2=DBL_MAX;
   for(int i=3;i<197;i++)
   {
      if(H[i]>H[i-1]&&H[i]>H[i-2]&&H[i]>H[i+1]&&H[i]>H[i+2])
      { if(sH1==0)sH1=H[i]; else if(sH2==0)sH2=H[i]; }
      if(L[i]<L[i-1]&&L[i]<L[i-2]&&L[i]<L[i+1]&&L[i]<L[i+2])
      { if(sL1==DBL_MAX)sL1=L[i]; else if(sL2==DBL_MAX)sL2=L[i]; }
      if(sH2>0&&sL2<DBL_MAX) break;
   }
   
   bool bullStruct=(sH2>0&&sL2<DBL_MAX&&sH1>sH2&&sL1>sL2);
   bool bearStruct=(sH2>0&&sL2<DBL_MAX&&sH1<sH2&&sL1<sL2);
   bool emBull=bF[1]>bS[1]&&C[1]>bT[1];
   bool emBear=bF[1]<bS[1]&&C[1]<bT[1];
   
   int bs=0,ss=0;
   if(bullStruct)bs++; if(emBull)bs++; if(trendHTF==1)bs++;
   if(bearStruct)ss++; if(emBear)ss++; if(trendHTF==-1)ss++;
   if(bs>=2) trendEntry=1; else if(ss>=2) trendEntry=-1; else trendEntry=0;
}

//+------------------------------------------------------------------+
//| SWING POINTS from M1 history                                      |
//+------------------------------------------------------------------+
void DetectSwings()
{
   ArrayResize(SWs,0);
   int lb = MathMin(InpOB_Lookback, InpHistoryDays*1440);
   double H[],L[];
   ArraySetAsSeries(H,true); ArraySetAsSeries(L,true);
   CopyHigh(_Symbol,PERIOD_M1,0,lb,H);
   CopyLow(_Symbol,PERIOD_M1,0,lb,L);
   
   for(int i=5;i<lb-5;i++)
   {
      bool isH=true, isL=true;
      for(int j=1;j<=5;j++)
      {
         if(H[i]<=H[i-j]||H[i]<=H[i+j]) isH=false;
         if(L[i]>=L[i-j]||L[i]>=L[i+j]) isL=false;
      }
      if(isH){ SSW s;s.p=H[i];s.t=iTime(_Symbol,PERIOD_M1,i);s.d=1;s.b=i;
               int n=ArraySize(SWs);ArrayResize(SWs,n+1);SWs[n]=s; }
      if(isL){ SSW s;s.p=L[i];s.t=iTime(_Symbol,PERIOD_M1,i);s.d=-1;s.b=i;
               int n=ArraySize(SWs);ArrayResize(SWs,n+1);SWs[n]=s; }
   }
}

//+------------------------------------------------------------------+
//| ORDER BLOCKS from M1 history (strict: 1.5x impulse + volume)     |
//+------------------------------------------------------------------+
void DetectOBs()
{
   ArrayResize(OBs,0);
   int lb=MathMin(InpOB_Lookback,InpHistoryDays*1440);
   double O[],H[],L[],C[]; long V[];
   ArraySetAsSeries(O,true);ArraySetAsSeries(H,true);ArraySetAsSeries(L,true);
   ArraySetAsSeries(C,true);ArraySetAsSeries(V,true);
   CopyOpen(_Symbol,PERIOD_M1,0,lb,O);CopyHigh(_Symbol,PERIOD_M1,0,lb,H);
   CopyLow(_Symbol,PERIOD_M1,0,lb,L);CopyClose(_Symbol,PERIOD_M1,0,lb,C);
   CopyTickVolume(_Symbol,PERIOD_M1,0,lb,V);
   
   double av=0; for(int i=1;i<=100&&i<lb;i++) av+=(double)V[i]; av/=100; if(av<=0)av=1;
   
   for(int i=2;i<lb-2;i++)
   {
      double bI=MathAbs(C[i]-O[i]),bP=MathAbs(C[i-1]-O[i-1]);
      // Bullish OB
      if(C[i]<O[i]&&C[i-1]>O[i-1]&&bP>bI*1.5&&(double)V[i-1]>av*1.2)
      {
         bool mit=false;
         for(int k=i-2;k>=1;k--) if(L[k]<L[i]){mit=true;break;}
         if(!mit){ SOB o;o.hi=H[i];o.lo=L[i];o.t=iTime(_Symbol,PERIOD_M1,i);o.d=1;o.str=(double)V[i-1]/av;
                   int n=ArraySize(OBs);ArrayResize(OBs,n+1);OBs[n]=o; }
      }
      // Bearish OB
      if(C[i]>O[i]&&C[i-1]<O[i-1]&&bP>bI*1.5&&(double)V[i-1]>av*1.2)
      {
         bool mit=false;
         for(int k=i-2;k>=1;k--) if(H[k]>H[i]){mit=true;break;}
         if(!mit){ SOB o;o.hi=H[i];o.lo=L[i];o.t=iTime(_Symbol,PERIOD_M1,i);o.d=-1;o.str=(double)V[i-1]/av;
                   int n=ArraySize(OBs);ArrayResize(OBs,n+1);OBs[n]=o; }
      }
   }
   // Sort+cap
   for(int i=0;i<ArraySize(OBs)-1;i++)
     for(int j=0;j<ArraySize(OBs)-i-1;j++)
       if(OBs[j].str<OBs[j+1].str){SOB t=OBs[j];OBs[j]=OBs[j+1];OBs[j+1]=t;}
   if(ArraySize(OBs)>15) ArrayResize(OBs,15);
}

//+------------------------------------------------------------------+
//| FVG                                                               |
//+------------------------------------------------------------------+
void DetectFVGs()
{
   ArrayResize(FVGs,0);
   int lb=MathMin(InpOB_Lookback,InpHistoryDays*1440);
   double H[],L[];ArraySetAsSeries(H,true);ArraySetAsSeries(L,true);
   CopyHigh(_Symbol,PERIOD_M1,0,lb,H);CopyLow(_Symbol,PERIOD_M1,0,lb,L);
   double pt=si.Point(),mg=InpFVG_MinGap*pt;
   
   for(int i=2;i<lb-1;i++)
   {
      double bt=L[i-1],bb=H[i+1];
      if(bb<bt&&(bt-bb)>=mg)
      {
         bool f=false; for(int k=i-2;k>=1;k--) if(L[k]<=bb){f=true;break;}
         if(!f){ SFVG g;g.hi=bt;g.lo=bb;g.t=iTime(_Symbol,PERIOD_M1,i);g.d=1;
                 int n=ArraySize(FVGs);ArrayResize(FVGs,n+1);FVGs[n]=g; }
      }
      double st=L[i+1],sb=H[i-1];
      if(st>sb&&(st-sb)>=mg)
      {
         bool f=false; for(int k=i-2;k>=1;k--) if(H[k]>=st){f=true;break;}
         if(!f){ SFVG g;g.hi=st;g.lo=sb;g.t=iTime(_Symbol,PERIOD_M1,i);g.d=-1;
                 int n=ArraySize(FVGs);ArrayResize(FVGs,n+1);FVGs[n]=g; }
      }
   }
   if(ArraySize(FVGs)>15) ArrayResize(FVGs,15);
}

//+------------------------------------------------------------------+
//| SNR                                                               |
//+------------------------------------------------------------------+
void DetectSNRs()
{
   ArrayResize(SNRs,0);
   int hb=InpHistoryDays*24+10;
   double H[],L[];ArraySetAsSeries(H,true);ArraySetAsSeries(L,true);
   CopyHigh(_Symbol,htfTF,0,hb,H);CopyLow(_Symbol,htfTF,0,hb,L);
   double pt=si.Point(),z=InpSNR_Zone*pt;
   double raw[];int rc=0;
   for(int i=2;i<hb-2;i++)
   {
      if(H[i]>=H[i-1]&&H[i]>=H[i+1]&&H[i]>=H[i-2]&&H[i]>=H[i+2])
      {ArrayResize(raw,rc+1);raw[rc++]=H[i];}
      if(L[i]<=L[i-1]&&L[i]<=L[i+1]&&L[i]<=L[i-2]&&L[i]<=L[i+2])
      {ArrayResize(raw,rc+1);raw[rc++]=L[i];}
   }
   for(int i=0;i<ArraySize(SWs)&&i<60;i++)
   {ArrayResize(raw,rc+1);raw[rc++]=SWs[i].p;}
   
   for(int i=0;i<rc;i++)
   {
      bool mg=false;
      for(int j=0;j<ArraySize(SNRs);j++)
        if(MathAbs(raw[i]-SNRs[j].p)<z){SNRs[j].tc++;SNRs[j].p=(SNRs[j].p*(SNRs[j].tc-1)+raw[i])/SNRs[j].tc;mg=true;break;}
      if(!mg){SSNR s;s.p=raw[i];s.tc=1;s.tp=raw[i]<si.Ask()?1:-1;
              int n=ArraySize(SNRs);ArrayResize(SNRs,n+1);SNRs[n]=s;}
   }
   for(int i=ArraySize(SNRs)-1;i>=0;i--)
     if(SNRs[i].tc<InpSNR_Touch)
     {for(int j=i;j<ArraySize(SNRs)-1;j++)SNRs[j]=SNRs[j+1];ArrayResize(SNRs,ArraySize(SNRs)-1);}
}

//+------------------------------------------------------------------+
//| LIQUIDITY                                                         |
//+------------------------------------------------------------------+
void DetectLIQs()
{
   ArrayResize(LIQs,0);
   double pt=si.Point(),tol=4*pt;
   for(int i=0;i<ArraySize(SWs)&&i<100;i++)
     for(int j=i+1;j<ArraySize(SWs)&&j<100;j++)
       if(SWs[i].d==SWs[j].d&&MathAbs(SWs[i].p-SWs[j].p)<tol)
       {
         bool ex=false;
         for(int k=0;k<ArraySize(LIQs);k++) if(MathAbs(LIQs[k].p-SWs[i].p)<tol){ex=true;break;}
         if(!ex)
         {
           SLIQ l;l.p=(SWs[i].p+SWs[j].p)/2;l.t=SWs[i].t;l.d=SWs[i].d;
           double h1=iHigh(_Symbol,PERIOD_M1,1),l1=iLow(_Symbol,PERIOD_M1,1);
           bool sw=false;
           if(l.d==1&&h1>l.p+tol)sw=true;
           if(l.d==-1&&l1<l.p-tol)sw=true;
           if(!sw){int n=ArraySize(LIQs);ArrayResize(LIQs,n+1);LIQs[n]=l;}
         }
       }
}

//+------------------------------------------------------------------+
//| FIB OTE                                                           |
//+------------------------------------------------------------------+
bool IsFibOTE(double price,double &fSL,double &fTP)
{
   if(ArraySize(SWs)<4) return false;
   double sH=0,sL=DBL_MAX; int sHi=-1,sLi=-1;
   for(int i=0;i<ArraySize(SWs)&&i<40;i++)
   {if(SWs[i].d==1&&SWs[i].p>sH){sH=SWs[i].p;sHi=SWs[i].b;}
    if(SWs[i].d==-1&&SWs[i].p<sL){sL=SWs[i].p;sLi=SWs[i].b;}}
   if(sH==0||sL==DBL_MAX) return false;
   double rng=sH-sL,pt=si.Point();
   if(rng<40*pt) return false;
   double zw=InpFib_Zone*pt;
   if(trendEntry==1&&sLi>sHi)
   {double f1=sH-rng*0.618,f2=sH-rng*0.786;
    if(price>=f2-zw&&price<=f1+zw){fSL=sL-10*pt;fTP=sH+rng*0.272;return true;}}
   if(trendEntry==-1&&sHi>sLi)
   {double f1=sL+rng*0.618,f2=sL+rng*0.786;
    if(price>=f1-zw&&price<=f2+zw){fSL=sH+10*pt;fTP=sL-rng*0.272;return true;}}
   return false;
}

//+------------------------------------------------------------------+
//| ASIAN RANGE                                                       |
//+------------------------------------------------------------------+
void CalcAsian()
{
   MqlDateTime dt;TimeToStruct(TimeCurrent(),dt);
   asianHi=0;asianLo=DBL_MAX;
   for(int i=1;i<=480;i++)
   {
      datetime bt=iTime(_Symbol,PERIOD_M1,i);if(bt==0)break;
      MqlDateTime bd;TimeToStruct(bt,bd);
      if(bd.hour>=0&&bd.hour<8&&bd.day==dt.day)
      {double h=iHigh(_Symbol,PERIOD_M1,i),l=iLow(_Symbol,PERIOD_M1,i);
       if(h>asianHi)asianHi=h;if(l<asianLo)asianLo=l;}
      else if(bd.day!=dt.day)break;
   }
}

//+------------------------------------------------------------------+
//| ═══════ WEIGHTED SCORING SYSTEM ═══════                          |
//| Each signal gets a WEIGHT, not just 0/1                          |
//| Total score must reach InpMinScore to enter                      |
//+------------------------------------------------------------------+
int ScoreAndDecide()
{
   double ask=si.Ask(),bid=si.Bid(),pt=si.Point();
   
   int bullScore=0, bearScore=0;
   // Reset breakdown
   sc_Trend=0;sc_Struct=0;sc_OB=0;sc_FVG=0;sc_Fib=0;
   sc_SNR=0;sc_Liq=0;sc_EMA=0;sc_RSI=0;sc_MACD=0;
   sc_Stoch=0;sc_Engulf=0;sc_Vol=0;
   
   //=== 1. HTF TREND (highest weight) ===
   if(trendHTF==1)  { bullScore += InpW_Trend; sc_Trend = InpW_Trend; }
   if(trendHTF==-1) { bearScore += InpW_Trend; sc_Trend = -InpW_Trend; }
   
   //=== 2. MARKET STRUCTURE ===
   if(trendEntry==1)  { bullScore += InpW_Structure; sc_Struct = InpW_Structure; }
   if(trendEntry==-1) { bearScore += InpW_Structure; sc_Struct = -InpW_Structure; }
   
   //=== 3. ORDER BLOCK ===
   for(int i=0;i<ArraySize(OBs);i++)
   {
      if(OBs[i].d==1&&bid>=OBs[i].lo&&bid<=OBs[i].hi)
      { bullScore+=InpW_OB; sc_OB=InpW_OB; break; }
      if(OBs[i].d==-1&&ask>=OBs[i].lo&&ask<=OBs[i].hi)
      { bearScore+=InpW_OB; sc_OB=-InpW_OB; break; }
   }
   
   //=== 4. FAIR VALUE GAP ===
   for(int i=0;i<ArraySize(FVGs);i++)
   {
      if(FVGs[i].d==1&&bid>=FVGs[i].lo&&bid<=FVGs[i].hi)
      { bullScore+=InpW_FVG; sc_FVG=InpW_FVG; break; }
      if(FVGs[i].d==-1&&ask>=FVGs[i].lo&&ask<=FVGs[i].hi)
      { bearScore+=InpW_FVG; sc_FVG=-InpW_FVG; break; }
   }
   
   //=== 5. FIBONACCI OTE ===
   double fSL,fTP;
   if(IsFibOTE(bid,fSL,fTP))
   {
      if(trendEntry==1)  { bullScore+=InpW_Fib; sc_Fib=InpW_Fib; }
      if(trendEntry==-1) { bearScore+=InpW_Fib; sc_Fib=-InpW_Fib; }
   }
   
   //=== 6. SNR ===
   double zone=InpSNR_Zone*pt;
   for(int i=0;i<ArraySize(SNRs);i++)
   {
      if(SNRs[i].tp==1&&bid>=SNRs[i].p-zone&&bid<=SNRs[i].p+zone)
      { bullScore+=InpW_SNR; sc_SNR=InpW_SNR; break; }
      if(SNRs[i].tp==-1&&ask>=SNRs[i].p-zone&&ask<=SNRs[i].p+zone)
      { bearScore+=InpW_SNR; sc_SNR=-InpW_SNR; break; }
   }
   
   //=== 7. LIQUIDITY SWEEP ===
   double cls[];ArraySetAsSeries(cls,true);CopyClose(_Symbol,PERIOD_M1,0,5,cls);
   for(int i=0;i<ArraySize(LIQs);i++)
   {
      if(LIQs[i].d==-1&&iLow(_Symbol,PERIOD_M1,1)<LIQs[i].p&&cls[1]>LIQs[i].p)
      { bullScore+=InpW_Liq; sc_Liq=InpW_Liq; break; }
      if(LIQs[i].d==1&&iHigh(_Symbol,PERIOD_M1,1)>LIQs[i].p&&cls[1]<LIQs[i].p)
      { bearScore+=InpW_Liq; sc_Liq=-InpW_Liq; break; }
   }
   
   //=== 8. EMA CROSS ===
   if(bF[1]>bS[1]&&bF[2]<=bS[2]) { bullScore+=InpW_EMA; sc_EMA=InpW_EMA; }
   if(bF[1]<bS[1]&&bF[2]>=bS[2]) { bearScore+=InpW_EMA; sc_EMA=-InpW_EMA; }
   
   //=== 9. RSI ===
   if(bRSI[1]<30||(bRSI[1]<40&&bRSI[1]>bRSI[2])) { bullScore+=InpW_RSI; sc_RSI=InpW_RSI; }
   if(bRSI[1]>70||(bRSI[1]>60&&bRSI[1]<bRSI[2])) { bearScore+=InpW_RSI; sc_RSI=-InpW_RSI; }
   
   //=== 10. MACD ===
   if(bMM[1]>bMS[1]&&bMM[2]<=bMS[2]) { bullScore+=InpW_MACD; sc_MACD=InpW_MACD; }
   if(bMM[1]<bMS[1]&&bMM[2]>=bMS[2]) { bearScore+=InpW_MACD; sc_MACD=-InpW_MACD; }
   
   //=== 11. STOCHASTIC ===
   if(bSK[1]>bSD[1]&&bSK[2]<=bSD[2]&&bSK[1]<30) { bullScore+=InpW_Stoch; sc_Stoch=InpW_Stoch; }
   if(bSK[1]<bSD[1]&&bSK[2]>=bSD[2]&&bSK[1]>70) { bearScore+=InpW_Stoch; sc_Stoch=-InpW_Stoch; }
   
   //=== 12. ENGULFING / PIN BAR ===
   {
      double o[],h[],l[],c[];
      ArraySetAsSeries(o,true);ArraySetAsSeries(h,true);ArraySetAsSeries(l,true);ArraySetAsSeries(c,true);
      CopyOpen(_Symbol,entryTF,0,5,o);CopyHigh(_Symbol,entryTF,0,5,h);
      CopyLow(_Symbol,entryTF,0,5,l);CopyClose(_Symbol,entryTF,0,5,c);
      double b1=MathAbs(c[1]-o[1]),b2=MathAbs(c[2]-o[2]);
      double wUp=h[1]-MathMax(c[1],o[1]),wDn=MathMin(c[1],o[1])-l[1];
      double rng=h[1]-l[1]; if(rng<=0)rng=1;
      
      if(c[1]>o[1]&&c[2]<o[2]&&b1>b2*1.2&&c[1]>o[2]) {bullScore+=InpW_Engulf;sc_Engulf=InpW_Engulf;}
      if(c[1]<o[1]&&c[2]>o[2]&&b1>b2*1.2&&c[1]<o[2]) {bearScore+=InpW_Engulf;sc_Engulf=-InpW_Engulf;}
      if(wDn>b1*2&&wDn>rng*0.6) {bullScore+=InpW_Engulf;sc_Engulf=InpW_Engulf;}
      if(wUp>b1*2&&wUp>rng*0.6) {bearScore+=InpW_Engulf;sc_Engulf=-InpW_Engulf;}
   }
   
   //=== 13. VOLUME CONFIRMATION ===
   {
      long vol[];ArraySetAsSeries(vol,true);
      CopyTickVolume(_Symbol,entryTF,0,20,vol);
      double avgV=0; for(int i=2;i<=11;i++) avgV+=(double)vol[i]; avgV/=10;
      if(avgV>0&&(double)vol[1]>avgV*1.3)
      {
         double c[];ArraySetAsSeries(c,true);CopyClose(_Symbol,entryTF,0,3,c);
         double o[];ArraySetAsSeries(o,true);CopyOpen(_Symbol,entryTF,0,3,o);
         if(c[1]>o[1]) { bullScore+=InpW_Volume; sc_Vol=InpW_Volume; }
         if(c[1]<o[1]) { bearScore+=InpW_Volume; sc_Vol=-InpW_Volume; }
      }
   }
   
   lastBullScore = bullScore;
   lastBearScore = bearScore;
   
   //=== DECISION ===
   int dir = 0;
   
   // MUST meet minimum score AND align with HTF trend
   if(bullScore >= InpMinScore && bullScore > bearScore && trendHTF >= 0)
      dir = 1;
   else if(bearScore >= InpMinScore && bearScore > bullScore && trendHTF <= 0)
      dir = -1;
   
   if(dir != 0)
   {
      int sc = dir==1?bullScore:bearScore;
      Print("══ ", (dir==1?"BUY":"SELL"), " ══ Score:", sc, "/", InpMinScore, "+");
      Print("   Trend:", sc_Trend, " Struct:", sc_Struct, " OB:", sc_OB,
            " FVG:", sc_FVG, " Fib:", sc_Fib, " SNR:", sc_SNR,
            " Liq:", sc_Liq, " EMA:", sc_EMA, " RSI:", sc_RSI,
            " MACD:", sc_MACD, " Stoch:", sc_Stoch,
            " Engulf:", sc_Engulf, " Vol:", sc_Vol);
   }
   
   return dir;
}

//+------------------------------------------------------------------+
//| OPEN TRADE                                                        |
//+------------------------------------------------------------------+
void OpenTrade(int dir)
{
   double ask=si.Ask(),bid=si.Bid(),pt=si.Point();
   double atr=bATR[1]; if(atr<=0) return;
   double slD=atr*InpATR_SL;
   double sl=0,tp=0;
   double fSL=0,fTP=0; bool hf=IsFibOTE(bid,fSL,fTP);
   
   if(dir==1)
   {
      sl=bid-slD;
      for(int i=0;i<ArraySize(OBs);i++)
        if(OBs[i].d==1&&OBs[i].lo<bid&&OBs[i].lo-5*pt>sl&&(bid-OBs[i].lo)<slD*2)
          sl=OBs[i].lo-5*pt;
      if(hf&&fSL>0&&fSL>sl&&fSL<bid) sl=fSL;
      double asl=bid-sl;
      if(asl<10*pt){asl=10*pt;sl=bid-asl;}
      tp=bid+asl*InpBaseRR;
      for(int i=0;i<ArraySize(SNRs);i++)
        if(SNRs[i].tp==-1&&SNRs[i].p>bid&&SNRs[i].p<tp)
        { double at=SNRs[i].p-3*pt; if((at-bid)>=asl*1.5) tp=at; }
      double lot=CalcLot(asl);
      sl=NormalizeDouble(sl,si.Digits());tp=NormalizeDouble(tp,si.Digits());
      if(tr.Buy(lot,_Symbol,ask,sl,tp,"SM7_BUY"))
        Print("✓ BUY ",lot," SL:",sl," TP:",tp," RR:",DoubleToString((tp-ask)/asl,1));
   }
   else
   {
      sl=ask+slD;
      for(int i=0;i<ArraySize(OBs);i++)
        if(OBs[i].d==-1&&OBs[i].hi>ask&&OBs[i].hi+5*pt<sl&&(OBs[i].hi-ask)<slD*2)
          sl=OBs[i].hi+5*pt;
      if(hf&&fSL>0&&fSL<sl&&fSL>ask) sl=fSL;
      double asl=sl-ask;
      if(asl<10*pt){asl=10*pt;sl=ask+asl;}
      tp=ask-asl*InpBaseRR;
      for(int i=0;i<ArraySize(SNRs);i++)
        if(SNRs[i].tp==1&&SNRs[i].p<ask&&SNRs[i].p>tp)
        { double at=SNRs[i].p+3*pt; if((ask-at)>=asl*1.5) tp=at; }
      double lot=CalcLot(asl);
      sl=NormalizeDouble(sl,si.Digits());tp=NormalizeDouble(tp,si.Digits());
      if(tr.Sell(lot,_Symbol,bid,sl,tp,"SM7_SELL"))
        Print("✓ SELL ",lot," SL:",sl," TP:",tp," RR:",DoubleToString((bid-tp)/asl,1));
   }
}

double CalcLot(double slD)
{
   double bal=ai.Balance(),tv=si.TickValue(),ts=si.TickSize();
   double mn=si.LotsMin(),mx=MathMin(si.LotsMax(),InpMaxLot),stp=si.LotsStep();
   if(tv<=0||ts<=0||slD<=0) return mn;
   double r=bal*GetRiskPct()/100.0;
   double lot=r/((slD/ts)*tv);
   lot=MathFloor(lot/stp)*stp;
   lot=MathMax(lot,mn);lot=MathMin(lot,mx);
   double mg=0;
   if(OrderCalcMargin(ORDER_TYPE_BUY,_Symbol,lot,si.Ask(),mg))
     if(mg>bal*0.3) lot=mn;
   return NormalizeDouble(lot,2);
}

//+------------------------------------------------------------------+
//| MANAGE — 3-layer BE + trail + time close                         |
//+------------------------------------------------------------------+
void ManagePositions()
{
   double pt=si.Point();
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!pi.SelectByIndex(i)) continue;
      if(pi.Magic()!=InpMagic||pi.Symbol()!=_Symbol) continue;
      double op=pi.PriceOpen(),cSL=pi.StopLoss(),cTP=pi.TakeProfit();
      double prof=pi.Profit(); datetime ot=pi.Time(); ulong tk=pi.Ticket();
      
      if(pi.PositionType()==POSITION_TYPE_BUY)
      {
         double bid=si.Bid(),pips=(bid-op)/pt;
         if(InpUseBE&&pips>=InpBE1_At&&cSL<op)
         {double ns=NormalizeDouble(op+InpBE1_Lock*pt,si.Digits());if(ns>cSL)tr.PositionModify(tk,ns,cTP);}
         if(InpUseBE&&pips>=InpBE2_At)
         {double ns=NormalizeDouble(op+InpBE2_Lock*pt,si.Digits());if(ns>cSL)tr.PositionModify(tk,ns,cTP);}
         if(InpUseBE&&pips>=InpBE3_At)
         {double ns=NormalizeDouble(op+InpBE3_Lock*pt,si.Digits());if(ns>cSL)tr.PositionModify(tk,ns,cTP);}
         if(InpTrail&&pips>=InpTrailStart)
         {double ns=NormalizeDouble(bid-InpTrailStep*pt,si.Digits());if(ns>cSL+pt)tr.PositionModify(tk,ns,cTP);}
         if(InpTimeClose&&prof>=InpTC_MinProf)
         {int el=(int)(TimeCurrent()-ot)/60;if(el>=InpTC_Min)tr.PositionClose(tk);}
      }
      else
      {
         double ask=si.Ask(),pips=(op-ask)/pt;
         if(InpUseBE&&pips>=InpBE1_At&&(cSL>op||cSL==0))
         {double ns=NormalizeDouble(op-InpBE1_Lock*pt,si.Digits());if(ns<cSL||cSL==0)tr.PositionModify(tk,ns,cTP);}
         if(InpUseBE&&pips>=InpBE2_At)
         {double ns=NormalizeDouble(op-InpBE2_Lock*pt,si.Digits());if(ns<cSL||cSL==0)tr.PositionModify(tk,ns,cTP);}
         if(InpUseBE&&pips>=InpBE3_At)
         {double ns=NormalizeDouble(op-InpBE3_Lock*pt,si.Digits());if(ns<cSL||cSL==0)tr.PositionModify(tk,ns,cTP);}
         if(InpTrail&&pips>=InpTrailStart)
         {double ns=NormalizeDouble(ask+InpTrailStep*pt,si.Digits());if(ns<cSL-pt||cSL==0)tr.PositionModify(tk,ns,cTP);}
         if(InpTimeClose&&prof>=InpTC_MinProf)
         {int el=(int)(TimeCurrent()-ot)/60;if(el>=InpTC_Min)tr.PositionClose(tk);}
      }
   }
}

//+------------------------------------------------------------------+
//| CHART DRAWING (toggleable)                                        |
//+------------------------------------------------------------------+
void DrawChart()
{
   ObjectsDeleteAll(0,PFX);
   datetime now=TimeCurrent(),fut=now+7200;
   
   if(InpShowOB)
     for(int i=0;i<ArraySize(OBs);i++)
     {string n=PFX+"OB"+IntegerToString(i);
      color c=OBs[i].d==1?InpClrBullOB:InpClrBearOB;
      ObjectCreate(0,n,OBJ_RECTANGLE,0,OBs[i].t,OBs[i].hi,fut,OBs[i].lo);
      ObjectSetInteger(0,n,OBJPROP_COLOR,c);ObjectSetInteger(0,n,OBJPROP_FILL,true);
      ObjectSetInteger(0,n,OBJPROP_BACK,true);
      ObjectSetString(0,n,OBJPROP_TOOLTIP,(OBs[i].d==1?"BULL":"BEAR")+" OB s:"+DoubleToString(OBs[i].str,1));}
   
   if(InpShowFVG)
     for(int i=0;i<ArraySize(FVGs);i++)
     {string n=PFX+"FVG"+IntegerToString(i);
      color c=FVGs[i].d==1?InpClrBullFVG:InpClrBearFVG;
      ObjectCreate(0,n,OBJ_RECTANGLE,0,FVGs[i].t,FVGs[i].hi,fut,FVGs[i].lo);
      ObjectSetInteger(0,n,OBJPROP_COLOR,c);ObjectSetInteger(0,n,OBJPROP_FILL,true);
      ObjectSetInteger(0,n,OBJPROP_BACK,true);}
   
   if(InpShowSNR)
     for(int i=0;i<ArraySize(SNRs);i++)
     {string n=PFX+"SNR"+IntegerToString(i);
      color c=SNRs[i].tp==1?InpClrSup:InpClrRes;
      ObjectCreate(0,n,OBJ_HLINE,0,0,SNRs[i].p);
      ObjectSetInteger(0,n,OBJPROP_COLOR,c);ObjectSetInteger(0,n,OBJPROP_STYLE,STYLE_DASH);
      ObjectSetInteger(0,n,OBJPROP_WIDTH,SNRs[i].tc>=3?2:1);}
   
   if(InpShowFib&&ArraySize(SWs)>=4)
   {
      double sH=0,sL=DBL_MAX;datetime sHt=0,sLt=0;
      for(int i=0;i<ArraySize(SWs)&&i<30;i++)
      {if(SWs[i].d==1&&SWs[i].p>sH){sH=SWs[i].p;sHt=SWs[i].t;}
       if(SWs[i].d==-1&&SWs[i].p<sL){sL=SWs[i].p;sLt=SWs[i].t;}}
      if(sH>0&&sL<DBL_MAX)
      {double r=sH-sL;
       double lv[]={0,0.236,0.382,0.5,0.618,0.786,1.0};
       string lb[]={"0%","23.6%","38.2%","50%","61.8%","78.6%","100%"};
       for(int i=0;i<7;i++)
       {double p=sH-r*lv[i];string n=PFX+"FIB"+IntegerToString(i);
        ObjectCreate(0,n,OBJ_HLINE,0,0,p);
        ObjectSetInteger(0,n,OBJPROP_COLOR,InpClrFib);
        ObjectSetInteger(0,n,OBJPROP_STYLE,(i==4||i==5)?STYLE_SOLID:STYLE_DOT);
        ObjectSetInteger(0,n,OBJPROP_WIDTH,(i==4||i==5)?2:1);
        string nl=PFX+"FL"+IntegerToString(i);
        ObjectCreate(0,nl,OBJ_TEXT,0,fut,p);ObjectSetString(0,nl,OBJPROP_TEXT,lb[i]);
        ObjectSetInteger(0,nl,OBJPROP_COLOR,InpClrFib);ObjectSetInteger(0,nl,OBJPROP_FONTSIZE,7);}
       string oz=PFX+"OTE";
       ObjectCreate(0,oz,OBJ_RECTANGLE,0,sLt<sHt?sLt:sHt,sH-r*0.618,fut,sH-r*0.786);
       ObjectSetInteger(0,oz,OBJPROP_COLOR,InpClrFib);
       ObjectSetInteger(0,oz,OBJPROP_FILL,true);ObjectSetInteger(0,oz,OBJPROP_BACK,true);}
   }
   
   if(InpShowLiq)
     for(int i=0;i<ArraySize(LIQs);i++)
     {string n=PFX+"LQ"+IntegerToString(i);
      ObjectCreate(0,n,OBJ_HLINE,0,0,LIQs[i].p);
      ObjectSetInteger(0,n,OBJPROP_COLOR,InpClrLiq);
      ObjectSetInteger(0,n,OBJPROP_STYLE,STYLE_DASHDOTDOT);}
   
   if(InpShowSwings)
   {
      int mx=MathMin(ArraySize(SWs),40);
      for(int i=0;i<mx;i++)
      {string n=PFX+"SW"+IntegerToString(i);
       if(SWs[i].d==1){ObjectCreate(0,n,OBJ_ARROW_DOWN,0,SWs[i].t,SWs[i].p);ObjectSetInteger(0,n,OBJPROP_COLOR,clrRed);}
       else{ObjectCreate(0,n,OBJ_ARROW_UP,0,SWs[i].t,SWs[i].p);ObjectSetInteger(0,n,OBJPROP_COLOR,clrLime);}
       ObjectSetInteger(0,n,OBJPROP_WIDTH,1);}
   }
   
   if(InpShowAsian&&asianHi>0&&asianLo<DBL_MAX)
   {MqlDateTime dt;TimeToStruct(now,dt);
    datetime ds=now-dt.hour*3600-dt.min*60-dt.sec;
    ObjectCreate(0,PFX+"ASIA",OBJ_RECTANGLE,0,ds,asianHi,ds+8*3600,asianLo);
    ObjectSetInteger(0,PFX+"ASIA",OBJPROP_COLOR,C'40,40,40');
    ObjectSetInteger(0,PFX+"ASIA",OBJPROP_FILL,true);ObjectSetInteger(0,PFX+"ASIA",OBJPROP_BACK,true);}
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| FILTERS                                                           |
//+------------------------------------------------------------------+
bool IsNews()
{
   if(!InpNews) return false;
   MqlDateTime dt;TimeToStruct(TimeCurrent(),dt);
   int cm=dt.hour*60+dt.min;
   if(dt.day_of_week==5&&dt.day<=7&&cm>=12*60&&cm<=16*60) return true;
   if(dt.day_of_week==3&&cm>=17*60&&cm<=21*60) return true;
   int nw=12*60+30;
   if(dt.day_of_week>=2&&dt.day_of_week<=5)
   {int d=MathAbs(cm-nw);if(d<=InpNewsBefore||(cm>nw&&d<=InpNewsAfter))return true;}
   if(ArraySize(bM1A)>10&&bM1A[1]>bM1A[5]*2.5) return true;
   return false;
}
bool SessOK(){MqlDateTime d;TimeToStruct(TimeCurrent(),d);return d.hour>=InpSessStart&&d.hour<InpSessEnd;}
bool FriOK(){if(!InpAvoidFri)return true;MqlDateTime d;TimeToStruct(TimeCurrent(),d);return !(d.day_of_week==5&&d.hour>=InpFriCut);}
bool CheckDD(){double e=ai.Equity();if(peakBal<=0)return false;double d=((peakBal-e)/peakBal)*100;
              if(d>=InpMaxDD){Print("!!! DD ",DoubleToString(d,1),"% !!!");CloseAll();return true;}return false;}
void CloseAll(){for(int i=PositionsTotal()-1;i>=0;i--)
  {if(!pi.SelectByIndex(i))continue;if(pi.Magic()!=InpMagic||pi.Symbol()!=_Symbol)continue;tr.PositionClose(pi.Ticket());}}
int CntPos(){int c=0;for(int i=PositionsTotal()-1;i>=0;i--)
  {if(!pi.SelectByIndex(i))continue;if(pi.Magic()!=InpMagic||pi.Symbol()!=_Symbol)continue;c++;}return c;}

//+------------------------------------------------------------------+
//| TIMER — Panel                                                     |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!InpShowPanel) { Comment(""); return; }
   
   double eq=ai.Equity(),bal=ai.Balance();
   double dd=peakBal>0?((peakBal-eq)/peakBal)*100:0;
   double pnl=bal-initBal;
   string tm=trendEntry==1?"BULL▲":trendEntry==-1?"BEAR▼":"FLAT═";
   string th=trendHTF==1?"BULL▲":trendHTF==-1?"BEAR▼":"FLAT═";
   
   string s="";
   s+="╔════════════════════════════════════════╗\n";
   s+="║ SmartMoney v7 — Weighted Scoring\n";
   s+="╠════════════════════════════════════════╣\n";
   s+="║ $"+DoubleToString(bal,2)+" | DD:"+DoubleToString(dd,1)+
      "% | "+(pnl>=0?"+":"")+DoubleToString(pnl,2)+"\n";
   s+="║ Pos:"+IntegerToString(CntPos())+"/"+IntegerToString(InpMaxTrades)+
      " | "+EnumToString(entryTF)+" → "+EnumToString(htfTF)+"\n";
   s+="╠════════════════════════════════════════╣\n";
   s+="║ Entry: "+tm+" | HTF: "+th+"\n";
   s+="║ OB:"+IntegerToString(ArraySize(OBs))+" FVG:"+IntegerToString(ArraySize(FVGs))+
      " SNR:"+IntegerToString(ArraySize(SNRs))+" LIQ:"+IntegerToString(ArraySize(LIQs))+"\n";
   
   if(InpShowScore)
   {
      s+="╠════════════════════════════════════════╣\n";
      s+="║ BULL:"+IntegerToString(lastBullScore)+
         " BEAR:"+IntegerToString(lastBearScore)+
         " (need "+IntegerToString(InpMinScore)+")\n";
      s+="║ Trend:"+IntegerToString(sc_Trend)+
         " Struct:"+IntegerToString(sc_Struct)+
         " OB:"+IntegerToString(sc_OB)+
         " FVG:"+IntegerToString(sc_FVG)+"\n";
      s+="║ Fib:"+IntegerToString(sc_Fib)+
         " SNR:"+IntegerToString(sc_SNR)+
         " Liq:"+IntegerToString(sc_Liq)+
         " EMA:"+IntegerToString(sc_EMA)+"\n";
      s+="║ RSI:"+IntegerToString(sc_RSI)+
         " MACD:"+IntegerToString(sc_MACD)+
         " Stoch:"+IntegerToString(sc_Stoch)+
         " Engf:"+IntegerToString(sc_Engulf)+
         " Vol:"+IntegerToString(sc_Vol)+"\n";
   }
   
   s+="╠════════════════════════════════════════╣\n";
   s+="║ Sess:"+(SessOK()?"✓":"✗")+
      " News:"+(IsNews()?"✗":"✓")+
      " Fri:"+(FriOK()?"✓":"✗")+"\n";
   s+="╚════════════════════════════════════════╝\n";
   
   Comment(s);
}

void OnTradeTransaction(const MqlTradeTransaction &t,const MqlTradeRequest &r,const MqlTradeResult &res)
{if(t.type==TRADE_TRANSACTION_DEAL_ADD)Print("═ DEAL:",EnumToString(t.deal_type)," P:",t.price," Bal:$",DoubleToString(ai.Balance(),2));}
//+------------------------------------------------------------------+
