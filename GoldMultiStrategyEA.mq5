//+------------------------------------------------------------------+
//|                                      GoldMultiStrategyEA.mq5     |
//|                        Multi-Strategy XAUUSD Expert Advisor      |
//|                        M1 Timeframe | Adaptive AI Scoring        |
//+------------------------------------------------------------------+
#property copyright   "GoldMultiStrategyEA"
#property link        ""
#property version     "1.00"
#property strict
#property description "Multi-strategy EA for XAUUSD M1: Aggressive Scalping, SMC/ICT, Sniper Reversal"
#property description "Features: AI Scoring, Adaptive Learning, Volatility Adaptation, Profit Protection"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_STRATEGY_MODE
  {
   MODE_AUTO        = 0,  // Auto (AI selects)
   MODE_SCALPING    = 1,  // Mode 1: Aggressive Scalping
   MODE_SMC         = 2,  // Mode 2: Smart Money (SMC/ICT)
   MODE_REVERSAL    = 3   // Mode 3: Sniper Reversal
  };

enum ENUM_VOLATILITY
  {
   VOL_LOW    = 0,
   VOL_MEDIUM = 1,
   VOL_HIGH   = 2
  };

enum ENUM_MARKET_STATE
  {
   STATE_TREND  = 0,
   STATE_RANGE  = 1
  };

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "═══════════ STRATEGY ═══════════"
input ENUM_STRATEGY_MODE InpStrategyMode  = MODE_AUTO;     // Strategy Mode
input bool               InpAutoMode      = true;          // Enable Auto Mode Switching

input group "═══════════ RISK MANAGEMENT ═══════════"
input double InpRiskPerTrade      = 1.0;    // Risk Per Trade (% of balance)
input int    InpMaxTrades         = 3;      // Max Simultaneous Trades
input double InpDailyProfitTarget = 3.0;    // Daily Profit Target (%, 0=off)
input double InpDailyLossLimit    = 2.0;    // Daily Loss Limit (%, 0=off)

input group "═══════════ VOLATILITY / ATR ═══════════"
input int    InpATRPeriod         = 14;     // ATR Period
input double InpATRLowThresh      = 0.8;    // ATR Low Threshold (multiplier of avg)
input double InpATRHighThresh     = 1.5;    // ATR High Threshold (multiplier of avg)

input group "═══════════ AI SCORING ═══════════"
input double InpMinScore          = 0.70;   // Minimum Trade Score (0-1)
input double InpWeightStructure   = 0.25;   // Weight: Structure
input double InpWeightLiquidity   = 0.25;   // Weight: Liquidity
input double InpWeightVolume      = 0.20;   // Weight: Volume
input double InpWeightVolatility  = 0.15;   // Weight: Volatility
input double InpWeightEntry       = 0.15;   // Weight: Entry Precision

input group "═══════════ TRADE MANAGEMENT ═══════════"
input bool   InpUseBreakeven      = true;   // Enable Break-Even at 1R
input bool   InpUsePartialClose   = true;   // Enable 50% Partial Close at 1.5R
input bool   InpUseTrailingStop   = true;   // Enable Trailing Stop
input double InpTrailingATRMult   = 1.5;    // Trailing Stop ATR Multiplier

input group "═══════════ PROFIT PROTECTION ═══════════"
input double InpReduceRiskAt3     = 3.0;    // Reduce risk 50% at this % profit
input double InpReduceRiskAt5     = 5.0;    // Reduce risk 70% at this % profit
input double InpDrawdownFromPeak  = 2.0;    // Stop trading: drawdown from peak (%)
input int    InpConsecWinReduce   = 3;      // Reduce lot after N consecutive wins

input group "═══════════ EXECUTION ═══════════"
input int    InpMagicNumber       = 77701;  // Magic Number
input double InpMaxSpread         = 35.0;   // Max Spread (points)
input bool   InpDebugLog          = true;   // Enable Debug Logs

//+------------------------------------------------------------------+
//| GLOBAL OBJECTS                                                   |
//+------------------------------------------------------------------+
CTrade         g_trade;
CPositionInfo  g_position;
CAccountInfo   g_account;
CSymbolInfo    g_symbol;

//+------------------------------------------------------------------+
//| TRADE HISTORY RECORD                                             |
//+------------------------------------------------------------------+
struct TradeRecord
  {
   double         score;
   double         pnl;
   bool           isWin;
   ENUM_STRATEGY_MODE mode;
  };

//+------------------------------------------------------------------+
//| GLOBAL STATE                                                     |
//+------------------------------------------------------------------+
// ATR / Volatility
int               g_atrHandle        = INVALID_HANDLE;
double            g_atrBuffer[];
double            g_currentATR       = 0;
ENUM_VOLATILITY   g_volatility       = VOL_MEDIUM;

// Market State
ENUM_MARKET_STATE g_marketState      = STATE_RANGE;
ENUM_STRATEGY_MODE g_activeMode      = MODE_SCALPING;

// Daily P&L tracking
double            g_dailyStartBalance = 0;
double            g_dailyProfit       = 0;
double            g_peakProfit        = 0;
bool              g_dailyStopped      = false;
int               g_lastDay           = -1;

// Consecutive wins
int               g_consecutiveWins   = 0;

// Adaptive learning
TradeRecord       g_tradeHistory[];
int               g_historyCount      = 0;
double            g_adaptiveThreshold = 0;  // added to InpMinScore
double            g_adaptiveLotMult   = 1.0;

// Signal weights (adaptive)
double            g_wStructure, g_wLiquidity, g_wVolume, g_wVolatility, g_wEntry;

// Candle data
double            g_open[], g_high[], g_low[], g_close[];
long              g_volume[];

// Tick volume handle
int               g_volHandle = INVALID_HANDLE;

// Bar tracking
datetime          g_lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Validate symbol
   if(StringFind(Symbol(), "XAUUSD") < 0 && StringFind(Symbol(), "GOLD") < 0)
     {
      Print("WARNING: This EA is designed for XAUUSD. Current symbol: ", Symbol());
     }

   // Initialize trade object
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   // Initialize symbol info
   g_symbol.Name(Symbol());
   g_symbol.Refresh();

   // Create ATR indicator
   g_atrHandle = iATR(Symbol(), PERIOD_M1, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("ERROR: Failed to create ATR indicator");
      return INIT_FAILED;
     }

   // Set array directions
   ArraySetAsSeries(g_atrBuffer, true);
   ArraySetAsSeries(g_open, true);
   ArraySetAsSeries(g_high, true);
   ArraySetAsSeries(g_low, true);
   ArraySetAsSeries(g_close, true);
   ArraySetAsSeries(g_volume, true);

   // Initialize weights
   g_wStructure  = InpWeightStructure;
   g_wLiquidity  = InpWeightLiquidity;
   g_wVolume     = InpWeightVolume;
   g_wVolatility = InpWeightVolatility;
   g_wEntry      = InpWeightEntry;

   // Initialize trade history
   ArrayResize(g_tradeHistory, 0);
   g_historyCount = 0;

   // Initialize daily tracking
   ResetDailyState();

   DebugLog("EA initialized. Mode: " + EnumToString(InpStrategyMode) +
            " | AutoMode: " + (InpAutoMode ? "ON" : "OFF") +
            " | Risk: " + DoubleToString(InpRiskPerTrade, 2) + "%");

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   DebugLog("EA deinitialized. Reason: " + IntegerToString(reason));
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Refresh symbol data
   g_symbol.Refresh();
   g_symbol.RefreshRates();

   // Check for new day → reset daily state
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_year != g_lastDay)
     {
      ResetDailyState();
      g_lastDay = dt.day_of_year;
     }

   // Update daily P&L
   UpdateDailyPnL();

   // Check daily limits
   if(g_dailyStopped)
      return;

   if(CheckDailyLimits())
     {
      g_dailyStopped = true;
      DebugLog("DAILY LIMIT HIT. Trading stopped for today.");
      return;
     }

   // Manage existing positions (every tick for responsiveness)
   ManageOpenPositions();

   // Only process signals on new bar
   if(!IsNewBar())
      return;

   // Load candle data
   if(!LoadCandleData())
      return;

   // Update ATR
   if(!UpdateATR())
      return;

   // Spread filter
   if(!CheckSpread())
      return;

   // Max trades check
   if(CountOpenPositions() >= InpMaxTrades)
      return;

   // Detect volatility regime
   DetectVolatility();

   // Detect market state
   DetectMarketState();

   // Determine active mode
   DetermineActiveMode();

   // Generate signal based on active mode
   int signal = 0;       // 1=BUY, -1=SELL, 0=none
   double sl = 0, tp = 0;
   double score = 0;

   switch(g_activeMode)
     {
      case MODE_SCALPING:
         signal = SignalScalping(sl, tp, score);
         break;
      case MODE_SMC:
         signal = SignalSMC(sl, tp, score);
         break;
      case MODE_REVERSAL:
         signal = SignalReversal(sl, tp, score);
         break;
      default:
         signal = SignalScalping(sl, tp, score);
         break;
     }

   // Apply adaptive threshold
   double effectiveThreshold = MathMin(InpMinScore + g_adaptiveThreshold, 0.95);

   if(signal != 0 && score >= effectiveThreshold)
     {
      ExecuteTrade(signal, sl, tp, score);
     }
  }

//+------------------------------------------------------------------+
//| UTILITY FUNCTIONS                                                |
//+------------------------------------------------------------------+
void DebugLog(string msg)
  {
   if(InpDebugLog)
      Print("[GMSE] ", msg);
  }

bool IsNewBar()
  {
   datetime currentBarTime = iTime(Symbol(), PERIOD_M1, 0);
   if(currentBarTime == g_lastBarTime)
      return false;
   g_lastBarTime = currentBarTime;
   return true;
  }

bool LoadCandleData()
  {
   if(CopyOpen(Symbol(), PERIOD_M1, 0, 100, g_open) < 100)   return false;
   if(CopyHigh(Symbol(), PERIOD_M1, 0, 100, g_high) < 100)   return false;
   if(CopyLow(Symbol(), PERIOD_M1, 0, 100, g_low) < 100)     return false;
   if(CopyClose(Symbol(), PERIOD_M1, 0, 100, g_close) < 100) return false;
   if(CopyTickVolume(Symbol(), PERIOD_M1, 0, 100, g_volume) < 100) return false;
   return true;
  }

bool UpdateATR()
  {
   if(CopyBuffer(g_atrHandle, 0, 0, 50, g_atrBuffer) < 50)
      return false;
   g_currentATR = g_atrBuffer[1]; // completed bar
   return (g_currentATR > 0);
  }

bool CheckSpread()
  {
   double spread = g_symbol.Spread();
   if(spread > InpMaxSpread)
     {
      return false;
     }
   return true;
  }

int CountOpenPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(g_position.SelectByIndex(i))
        {
         if(g_position.Symbol() == Symbol() && g_position.Magic() == InpMagicNumber)
            count++;
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| DAILY P&L MANAGEMENT                                             |
//+------------------------------------------------------------------+
void ResetDailyState()
  {
   g_dailyStartBalance = g_account.Balance();
   g_dailyProfit        = 0;
   g_peakProfit         = 0;
   g_dailyStopped       = false;
   DebugLog("Daily state reset. Start balance: " + DoubleToString(g_dailyStartBalance, 2));
  }

void UpdateDailyPnL()
  {
   double equity = g_account.Equity();
   g_dailyProfit = ((equity - g_dailyStartBalance) / g_dailyStartBalance) * 100.0;
   if(g_dailyProfit > g_peakProfit)
      g_peakProfit = g_dailyProfit;
  }

bool CheckDailyLimits()
  {
   // Profit target
   if(InpDailyProfitTarget > 0 && g_dailyProfit >= InpDailyProfitTarget)
     {
      DebugLog("Daily profit target reached: " + DoubleToString(g_dailyProfit, 2) + "%");
      return true;
     }

   // Loss limit
   if(InpDailyLossLimit > 0 && g_dailyProfit <= -InpDailyLossLimit)
     {
      DebugLog("Daily loss limit hit: " + DoubleToString(g_dailyProfit, 2) + "%");
      return true;
     }

   // Drawdown from peak (anti-giveback)
   if(g_peakProfit > InpDrawdownFromPeak && (g_peakProfit - g_dailyProfit) >= InpDrawdownFromPeak)
     {
      DebugLog("Drawdown from peak exceeded. Peak: " + DoubleToString(g_peakProfit, 2) +
               "% Current: " + DoubleToString(g_dailyProfit, 2) + "%");
      return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| VOLATILITY DETECTION                                             |
//+------------------------------------------------------------------+
void DetectVolatility()
  {
   // Average ATR over last 50 bars
   double avgATR = 0;
   for(int i = 1; i <= 50; i++)
      avgATR += g_atrBuffer[i];
   avgATR /= 50.0;

   if(avgATR <= 0)
     {
      g_volatility = VOL_MEDIUM;
      return;
     }

   double ratio = g_currentATR / avgATR;

   if(ratio < InpATRLowThresh)
      g_volatility = VOL_LOW;
   else if(ratio > InpATRHighThresh)
      g_volatility = VOL_HIGH;
   else
      g_volatility = VOL_MEDIUM;
  }

//+------------------------------------------------------------------+
//| MARKET STATE DETECTION                                           |
//+------------------------------------------------------------------+
void DetectMarketState()
  {
   // Check for higher highs / higher lows (trend) vs range
   // Use last 20 bars, look at swing points
   int swingCount = 0;
   int hhCount = 0, hlCount = 0, lhCount = 0, llCount = 0;

   for(int i = 3; i < 18; i++)
     {
      // Swing high
      if(g_high[i] > g_high[i-1] && g_high[i] > g_high[i-2] &&
         g_high[i] > g_high[i+1] && g_high[i] > g_high[i+2])
        {
         swingCount++;
         // Compare with previous swing
         for(int j = i + 3; j < 20; j++)
           {
            if(g_high[j] > g_high[j-1] && g_high[j] > g_high[j-2] &&
               g_high[j] > g_high[j+1] && g_high[j] > g_high[j+2])
              {
               if(g_high[i] > g_high[j]) hhCount++;
               else lhCount++;
               break;
              }
           }
        }

      // Swing low
      if(g_low[i] < g_low[i-1] && g_low[i] < g_low[i-2] &&
         g_low[i] < g_low[i+1] && g_low[i] < g_low[i+2])
        {
         for(int j = i + 3; j < 20; j++)
           {
            if(g_low[j] < g_low[j-1] && g_low[j] < g_low[j-2] &&
               g_low[j] < g_low[j+1] && g_low[j] < g_low[j+2])
              {
               if(g_low[i] > g_low[j]) hlCount++;
               else llCount++;
               break;
              }
           }
        }
     }

   // ATR rising check
   bool atrRising = (g_atrBuffer[1] > g_atrBuffer[5] * 1.1);

   // Determine state
   if((hhCount >= 1 && hlCount >= 1) || (lhCount >= 1 && llCount >= 1))
     {
      if(atrRising || g_volatility == VOL_HIGH)
         g_marketState = STATE_TREND;
      else
         g_marketState = STATE_TREND;
     }
   else
     {
      g_marketState = STATE_RANGE;
     }
  }

//+------------------------------------------------------------------+
//| AUTO MODE SWITCHING                                              |
//+------------------------------------------------------------------+
void DetermineActiveMode()
  {
   if(InpStrategyMode != MODE_AUTO && !InpAutoMode)
     {
      g_activeMode = InpStrategyMode;
      return;
     }

   // Auto mode logic
   if(g_marketState == STATE_TREND && g_volatility == VOL_HIGH)
     {
      g_activeMode = MODE_SCALPING;  // Aggressive breakout scalping
     }
   else if(g_marketState == STATE_TREND && (g_volatility == VOL_MEDIUM || g_volatility == VOL_LOW))
     {
      g_activeMode = MODE_SMC;       // Structural trading
     }
   else // STATE_RANGE or exhaustion
     {
      g_activeMode = MODE_REVERSAL;  // Reversal / mean reversion
     }

   // Override: Low volatility → avoid aggressive modes
   if(g_volatility == VOL_LOW && g_activeMode == MODE_SCALPING)
      g_activeMode = MODE_REVERSAL;
  }

//+------------------------------------------------------------------+
//| HELPER: Body / Wick ratios                                       |
//+------------------------------------------------------------------+
double CandleBody(int idx)
  {
   return MathAbs(g_close[idx] - g_open[idx]);
  }

double CandleRange(int idx)
  {
   return g_high[idx] - g_low[idx];
  }

double UpperWick(int idx)
  {
   return g_high[idx] - MathMax(g_open[idx], g_close[idx]);
  }

double LowerWick(int idx)
  {
   return MathMin(g_open[idx], g_close[idx]) - g_low[idx];
  }

bool IsBullish(int idx)
  {
   return g_close[idx] > g_open[idx];
  }

bool IsBearish(int idx)
  {
   return g_close[idx] < g_open[idx];
  }

double AverageVolume(int start, int count)
  {
   double sum = 0;
   for(int i = start; i < start + count && i < ArraySize(g_volume); i++)
      sum += (double)g_volume[i];
   return sum / (double)count;
  }

//+------------------------------------------------------------------+
//| HELPER: Support / Resistance detection                           |
//+------------------------------------------------------------------+
double FindNearestSupport(int lookback)
  {
   double minLow = g_low[1];
   for(int i = 2; i < lookback; i++)
     {
      // Swing low
      if(i + 2 < lookback)
        {
         if(g_low[i] < g_low[i-1] && g_low[i] < g_low[i+1])
           {
            if(g_close[1] > g_low[i]) // price above this level
              {
               return g_low[i];
              }
           }
        }
     }
   // Fallback: lowest low
   for(int i = 1; i < lookback; i++)
      if(g_low[i] < minLow) minLow = g_low[i];
   return minLow;
  }

double FindNearestResistance(int lookback)
  {
   double maxHigh = g_high[1];
   for(int i = 2; i < lookback; i++)
     {
      if(i + 2 < lookback)
        {
         if(g_high[i] > g_high[i-1] && g_high[i] > g_high[i+1])
           {
            if(g_close[1] < g_high[i])
              {
               return g_high[i];
              }
           }
        }
     }
   for(int i = 1; i < lookback; i++)
      if(g_high[i] > maxHigh) maxHigh = g_high[i];
   return maxHigh;
  }

//+------------------------------------------------------------------+
//| HELPER: Fibonacci levels                                         |
//+------------------------------------------------------------------+
double FibLevel(double swingHigh, double swingLow, double level)
  {
   return swingHigh - (swingHigh - swingLow) * level;
  }

//+------------------------------------------------------------------+
//| HELPER: Find swing high/low in range                             |
//+------------------------------------------------------------------+
double SwingHigh(int start, int count)
  {
   double val = g_high[start];
   for(int i = start; i < start + count && i < ArraySize(g_high); i++)
      if(g_high[i] > val) val = g_high[i];
   return val;
  }

double SwingLow(int start, int count)
  {
   double val = g_low[start];
   for(int i = start; i < start + count && i < ArraySize(g_low); i++)
      if(g_low[i] < val) val = g_low[i];
   return val;
  }

//+------------------------------------------------------------------+
//| MODE 1: AGGRESSIVE SCALPING SIGNAL                               |
//+------------------------------------------------------------------+
int SignalScalping(double &sl, double &tp, double &score)
  {
   int signal = 0;
   double ask = g_symbol.Ask();
   double bid = g_symbol.Bid();
   double point = g_symbol.Point();

   // Sub-scores
   double sStructure = 0, sLiquidity = 0, sVolume = 0, sVolatility = 0, sEntry = 0;

   // Average volume
   double avgVol = AverageVolume(2, 20);
   bool volumeSpike = ((double)g_volume[1] > avgVol * 1.5);

   // Momentum candle: body > 70% of range
   bool momentumBull = IsBullish(1) && CandleBody(1) > CandleRange(1) * 0.7;
   bool momentumBear = IsBearish(1) && CandleBody(1) > CandleRange(1) * 0.7;

   // Breakout detection: price breaks recent high/low
   double recentHigh = SwingHigh(2, 15);
   double recentLow  = SwingLow(2, 15);

   bool breakoutUp   = g_close[1] > recentHigh;
   bool breakoutDown = g_close[1] < recentLow;

   // Retest: after breakout, price pulls back slightly
   bool retestUp   = breakoutUp && (g_low[1] <= recentHigh + g_currentATR * 0.3);
   bool retestDown = breakoutDown && (g_high[1] >= recentLow - g_currentATR * 0.3);

   // Dynamic SL range: 50-120 points based on ATR
   double slPoints = MathMax(50, MathMin(120, g_currentATR / point));

   // Volatility adjustment
   if(g_volatility == VOL_LOW)
      slPoints *= 0.7;
   else if(g_volatility == VOL_HIGH)
      slPoints *= 1.3;

   // BUY SIGNAL
   if((breakoutUp || retestUp) && momentumBull && volumeSpike)
     {
      signal = 1;
      sl = ask - slPoints * point;
      tp = ask + slPoints * point * 2.0;  // 1:2 RR

      // Score components
      sStructure  = breakoutUp ? 0.8 : 0.5;
      sLiquidity  = (g_close[1] > recentHigh) ? 0.7 : 0.4;
      sVolume     = volumeSpike ? 0.9 : 0.4;
      sVolatility = (g_volatility == VOL_HIGH) ? 0.9 : (g_volatility == VOL_MEDIUM ? 0.6 : 0.3);
      sEntry      = retestUp ? 0.9 : 0.6;
     }
   // SELL SIGNAL
   else if((breakoutDown || retestDown) && momentumBear && volumeSpike)
     {
      signal = -1;
      sl = bid + slPoints * point;
      tp = bid - slPoints * point * 2.0;

      sStructure  = breakoutDown ? 0.8 : 0.5;
      sLiquidity  = (g_close[1] < recentLow) ? 0.7 : 0.4;
      sVolume     = volumeSpike ? 0.9 : 0.4;
      sVolatility = (g_volatility == VOL_HIGH) ? 0.9 : (g_volatility == VOL_MEDIUM ? 0.6 : 0.3);
      sEntry      = retestDown ? 0.9 : 0.6;
     }

   // Compute weighted score
   score = sStructure  * g_wStructure +
           sLiquidity  * g_wLiquidity +
           sVolume     * g_wVolume +
           sVolatility * g_wVolatility +
           sEntry      * g_wEntry;

   if(signal != 0)
      DebugLog("SCALP Signal: " + (signal > 0 ? "BUY" : "SELL") +
               " | Score: " + DoubleToString(score, 3) +
               " [S:" + DoubleToString(sStructure,2) +
               " L:" + DoubleToString(sLiquidity,2) +
               " V:" + DoubleToString(sVolume,2) +
               " Vol:" + DoubleToString(sVolatility,2) +
               " E:" + DoubleToString(sEntry,2) + "]");

   return signal;
  }

//+------------------------------------------------------------------+
//| MODE 2: SMC / ICT SIGNAL                                        |
//+------------------------------------------------------------------+
int SignalSMC(double &sl, double &tp, double &score)
  {
   int signal = 0;
   double ask = g_symbol.Ask();
   double bid = g_symbol.Bid();
   double point = g_symbol.Point();

   double sStructure = 0, sLiquidity = 0, sVolume = 0, sVolatility = 0, sEntry = 0;

   // ── BOS / CHOCH Detection ──
   // Break of Structure: price breaks previous swing
   double prevSwingHigh = SwingHigh(5, 20);
   double prevSwingLow  = SwingLow(5, 20);
   double nearSwingHigh = SwingHigh(1, 5);
   double nearSwingLow  = SwingLow(1, 5);

   bool bosUp   = g_close[1] > prevSwingHigh;  // Bullish BOS
   bool bosDown = g_close[1] < prevSwingLow;   // Bearish BOS

   // CHOCH: Change of character - break against trend
   bool chochBull = false, chochBear = false;
   if(g_marketState == STATE_TREND)
     {
      // In downtrend, a break of recent high = CHOCH bullish
      if(g_close[2] < g_close[5] && bosUp)
         chochBull = true;
      if(g_close[2] > g_close[5] && bosDown)
         chochBear = true;
     }

   // ── Liquidity Sweep ──
   // Price spikes beyond a level then reverses
   bool sweepLow  = (g_low[1] < prevSwingLow && g_close[1] > prevSwingLow);
   bool sweepHigh = (g_high[1] > prevSwingHigh && g_close[1] < prevSwingHigh);

   // ── Order Block Detection ──
   // Last bearish candle before bullish move (demand OB)
   bool demandOB = false, supplyOB = false;
   double obLevel = 0;

   for(int i = 2; i < 15; i++)
     {
      // Demand OB: bearish candle followed by strong bullish move
      if(IsBearish(i) && IsBullish(i-1) && CandleBody(i-1) > CandleBody(i) * 1.5)
        {
         if(g_close[1] >= g_low[i] && g_close[1] <= g_high[i])
           {
            demandOB = true;
            obLevel = g_low[i];
            break;
           }
        }
      // Supply OB
      if(IsBullish(i) && IsBearish(i-1) && CandleBody(i-1) > CandleBody(i) * 1.5)
        {
         if(g_close[1] >= g_low[i] && g_close[1] <= g_high[i])
           {
            supplyOB = true;
            obLevel = g_high[i];
            break;
           }
        }
     }

   // ── Fair Value Gap ──
   bool fvgBull = false, fvgBear = false;
   double fvgTop = 0, fvgBottom = 0;

   for(int i = 2; i < 15; i++)
     {
      // Bullish FVG: gap between candle[i+1] high and candle[i-1] low
      if(i + 1 < ArraySize(g_low))
        {
         if(g_low[i-1] > g_high[i+1]) // gap up
           {
            fvgBull = true;
            fvgTop = g_low[i-1];
            fvgBottom = g_high[i+1];
            if(g_close[1] >= fvgBottom && g_close[1] <= fvgTop)
              {
               fvgBull = true;
               break;
              }
            fvgBull = false;
           }
         if(g_high[i-1] < g_low[i+1]) // gap down
           {
            fvgBear = true;
            fvgTop = g_low[i+1];
            fvgBottom = g_high[i-1];
            if(g_close[1] >= fvgBottom && g_close[1] <= fvgTop)
              {
               fvgBear = true;
               break;
              }
            fvgBear = false;
           }
        }
     }

   // ── Fibonacci Confluence ──
   double swH = SwingHigh(1, 30);
   double swL = SwingLow(1, 30);
   double fib50  = FibLevel(swH, swL, 0.50);
   double fib618 = FibLevel(swH, swL, 0.618);
   bool   fibConfluence = (g_close[1] >= fib618 && g_close[1] <= fib50);

   // ── Volume ──
   double avgVol = AverageVolume(2, 20);
   bool volConfirm = ((double)g_volume[1] > avgVol * 1.2);

   // ── Signal Assembly ──
   // BUY: Bullish BOS/CHOCH + (sweep low or demand OB or bullish FVG) + confluence
   int bullPoints = 0;
   if(bosUp || chochBull) bullPoints += 2;
   if(sweepLow)           bullPoints += 2;
   if(demandOB)           bullPoints += 2;
   if(fvgBull)            bullPoints += 1;
   if(fibConfluence)      bullPoints += 1;
   if(volConfirm)         bullPoints += 1;

   int bearPoints = 0;
   if(bosDown || chochBear) bearPoints += 2;
   if(sweepHigh)            bearPoints += 2;
   if(supplyOB)             bearPoints += 2;
   if(fvgBear)              bearPoints += 1;
   if(fibConfluence)        bearPoints += 1;
   if(volConfirm)           bearPoints += 1;

   double slDist = g_currentATR * 2.0;

   if(bullPoints >= 4 && bullPoints > bearPoints)
     {
      signal = 1;
      // SL behind liquidity
      double liquidityLevel = (sweepLow) ? g_low[1] - g_currentATR * 0.5 :
                              (demandOB) ? obLevel - g_currentATR * 0.3 :
                              ask - slDist;
      sl = liquidityLevel;
      // TP: next liquidity zone (resistance)
      double nextLiq = FindNearestResistance(30);
      tp = (nextLiq > ask) ? nextLiq : ask + slDist * 2.0;

      // Ensure minimum 1:2 RR
      double risk = ask - sl;
      if(risk > 0 && (tp - ask) / risk < 2.0)
         tp = ask + risk * 2.0;
     }
   else if(bearPoints >= 4 && bearPoints > bullPoints)
     {
      signal = -1;
      double liquidityLevel = (sweepHigh) ? g_high[1] + g_currentATR * 0.5 :
                              (supplyOB) ? obLevel + g_currentATR * 0.3 :
                              bid + slDist;
      sl = liquidityLevel;
      double nextLiq = FindNearestSupport(30);
      tp = (nextLiq < bid) ? nextLiq : bid - slDist * 2.0;

      double risk = sl - bid;
      if(risk > 0 && (bid - tp) / risk < 2.0)
         tp = bid - risk * 2.0;
     }

   // Score
   sStructure  = MathMin(1.0, (double)(MathMax(bullPoints, bearPoints)) / 7.0);
   sLiquidity  = (sweepLow || sweepHigh) ? 0.9 : (demandOB || supplyOB) ? 0.7 : 0.3;
   sVolume     = volConfirm ? 0.8 : 0.4;
   sVolatility = (g_volatility == VOL_MEDIUM) ? 0.8 : (g_volatility == VOL_HIGH ? 0.6 : 0.5);
   sEntry      = fibConfluence ? 0.9 : (fvgBull || fvgBear) ? 0.7 : 0.4;

   score = sStructure  * g_wStructure +
           sLiquidity  * g_wLiquidity +
           sVolume     * g_wVolume +
           sVolatility * g_wVolatility +
           sEntry      * g_wEntry;

   if(signal != 0)
      DebugLog("SMC Signal: " + (signal > 0 ? "BUY" : "SELL") +
               " | BullPts:" + IntegerToString(bullPoints) +
               " BearPts:" + IntegerToString(bearPoints) +
               " | Score: " + DoubleToString(score, 3) +
               " | BOS:" + (bosUp||bosDown?"Y":"N") +
               " CHOCH:" + (chochBull||chochBear?"Y":"N") +
               " Sweep:" + (sweepLow||sweepHigh?"Y":"N") +
               " OB:" + (demandOB||supplyOB?"Y":"N") +
               " FVG:" + (fvgBull||fvgBear?"Y":"N") +
               " Fib:" + (fibConfluence?"Y":"N"));

   return signal;
  }

//+------------------------------------------------------------------+
//| MODE 3: SNIPER REVERSAL SIGNAL                                   |
//+------------------------------------------------------------------+
int SignalReversal(double &sl, double &tp, double &score)
  {
   int signal = 0;
   double ask = g_symbol.Ask();
   double bid = g_symbol.Bid();
   double point = g_symbol.Point();

   double sStructure = 0, sLiquidity = 0, sVolume = 0, sVolatility = 0, sEntry = 0;

   // ── Spike Detection ──
   // Large candle relative to ATR
   bool spike = CandleRange(1) > g_currentATR * 1.8;

   // ── Exhaustion Wick ──
   // Long wick relative to body → rejection
   double bodySize = CandleBody(1);
   double range = CandleRange(1);
   bool exhaustionWickUp   = (UpperWick(1) > bodySize * 2.0 && UpperWick(1) > range * 0.5);
   bool exhaustionWickDown = (LowerWick(1) > bodySize * 2.0 && LowerWick(1) > range * 0.5);

   // ── Strong SNR Level ──
   // Price near a significant support/resistance
   double support    = FindNearestSupport(40);
   double resistance = FindNearestResistance(40);
   double tolerance  = g_currentATR * 0.5;

   bool atSupport    = (g_close[1] <= support + tolerance && g_close[1] >= support - tolerance);
   bool atResistance = (g_close[1] >= resistance - tolerance && g_close[1] <= resistance + tolerance);

   // ── Volume Climax ──
   double avgVol = AverageVolume(2, 30);
   bool volumeClimax = ((double)g_volume[1] > avgVol * 2.0);

   // ── Mean Reversion Target ──
   // Simple: 20-bar moving average
   double sum20 = 0;
   for(int i = 1; i <= 20; i++)
      sum20 += g_close[i];
   double mean20 = sum20 / 20.0;

   // ── Signal Assembly ──
   // BUY REVERSAL: at support + exhaustion wick down + volume climax
   int bullRev = 0;
   if(atSupport)          bullRev += 2;
   if(exhaustionWickDown) bullRev += 2;
   if(spike)              bullRev += 1;
   if(volumeClimax)       bullRev += 2;
   if(g_close[1] < mean20) bullRev += 1; // below mean → room for reversion

   int bearRev = 0;
   if(atResistance)       bearRev += 2;
   if(exhaustionWickUp)   bearRev += 2;
   if(spike)              bearRev += 1;
   if(volumeClimax)       bearRev += 2;
   if(g_close[1] > mean20) bearRev += 1;

   if(bullRev >= 5 && bullRev > bearRev)
     {
      signal = 1;
      // SL beyond spike low
      sl = g_low[1] - g_currentATR * 0.5;
      // TP: mean reversion
      tp = mean20;
      // Ensure minimum 1:3 RR
      double risk = ask - sl;
      if(risk > 0)
        {
         if((tp - ask) / risk < 3.0)
            tp = ask + risk * 3.0;
        }
     }
   else if(bearRev >= 5 && bearRev > bullRev)
     {
      signal = -1;
      sl = g_high[1] + g_currentATR * 0.5;
      tp = mean20;
      double risk = sl - bid;
      if(risk > 0)
        {
         if((bid - tp) / risk < 3.0)
            tp = bid - risk * 3.0;
        }
     }

   // Score
   sStructure  = MathMin(1.0, (double)(MathMax(bullRev, bearRev)) / 7.0);
   sLiquidity  = (atSupport || atResistance) ? 0.9 : 0.3;
   sVolume     = volumeClimax ? 0.95 : 0.3;
   sVolatility = spike ? 0.8 : 0.4;
   sEntry      = (exhaustionWickUp || exhaustionWickDown) ? 0.9 : 0.4;

   score = sStructure  * g_wStructure +
           sLiquidity  * g_wLiquidity +
           sVolume     * g_wVolume +
           sVolatility * g_wVolatility +
           sEntry      * g_wEntry;

   if(signal != 0)
      DebugLog("REVERSAL Signal: " + (signal > 0 ? "BUY" : "SELL") +
               " | BullRev:" + IntegerToString(bullRev) +
               " BearRev:" + IntegerToString(bearRev) +
               " | Score: " + DoubleToString(score, 3) +
               " | Spike:" + (spike?"Y":"N") +
               " ExhWick:" + (exhaustionWickUp||exhaustionWickDown?"Y":"N") +
               " SNR:" + (atSupport||atResistance?"Y":"N") +
               " VolClimax:" + (volumeClimax?"Y":"N"));

   return signal;
  }

//+------------------------------------------------------------------+
//| LOT SIZE CALCULATION                                             |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
  {
   if(slDistance <= 0)
      return g_symbol.LotsMin();

   double balance = g_account.Balance();
   double riskPct = InpRiskPerTrade;

   // ── Profit Protection: reduce risk ──
   if(g_dailyProfit >= InpReduceRiskAt5 && InpReduceRiskAt5 > 0)
      riskPct *= 0.3;  // 70% reduction
   else if(g_dailyProfit >= InpReduceRiskAt3 && InpReduceRiskAt3 > 0)
      riskPct *= 0.5;  // 50% reduction

   // ── Consecutive wins reduction ──
   if(g_consecutiveWins >= InpConsecWinReduce && InpConsecWinReduce > 0)
      riskPct *= 0.8;

   // ── Adaptive lot multiplier ──
   riskPct *= g_adaptiveLotMult;

   double riskMoney = balance * riskPct / 100.0;
   double tickValue = g_symbol.TickValue();
   double tickSize  = g_symbol.TickSize();

   if(tickValue <= 0 || tickSize <= 0)
      return g_symbol.LotsMin();

   double lots = riskMoney / (slDistance / tickSize * tickValue);

   // Normalize
   double minLot  = g_symbol.LotsMin();
   double maxLot  = g_symbol.LotsMax();
   double lotStep = g_symbol.LotsStep();

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   return lots;
  }

//+------------------------------------------------------------------+
//| EXECUTE TRADE                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(int signal, double sl, double tp, double score)
  {
   double ask = g_symbol.Ask();
   double bid = g_symbol.Bid();
   double point = g_symbol.Point();

   // Sanitize SL/TP
   int digits = (int)g_symbol.Digits();
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   double price, slDist;
   string comment;

   if(signal == 1)
     {
      price  = ask;
      slDist = price - sl;
      comment = StringFormat("GMSE|%s|S%.2f", EnumToString(g_activeMode), score);
     }
   else
     {
      price  = bid;
      slDist = sl - price;
      comment = StringFormat("GMSE|%s|S%.2f", EnumToString(g_activeMode), score);
     }

   if(slDist <= 0)
     {
      DebugLog("Invalid SL distance. Skipping trade.");
      return;
     }

   double lots = CalculateLotSize(slDist);

   DebugLog("EXECUTING: " + (signal > 0 ? "BUY" : "SELL") +
            " | Lots: " + DoubleToString(lots, 2) +
            " | SL: " + DoubleToString(sl, digits) +
            " | TP: " + DoubleToString(tp, digits) +
            " | Score: " + DoubleToString(score, 3) +
            " | Mode: " + EnumToString(g_activeMode) +
            " | Vol: " + EnumToString(g_volatility) +
            " | State: " + EnumToString(g_marketState));

   bool result;
   if(signal == 1)
      result = g_trade.Buy(lots, Symbol(), price, sl, tp, comment);
   else
      result = g_trade.Sell(lots, Symbol(), price, sl, tp, comment);

   if(!result)
     {
      DebugLog("ORDER FAILED: " + IntegerToString(g_trade.ResultRetcode()) +
               " - " + g_trade.ResultRetcodeDescription());
     }
   else
     {
      DebugLog("ORDER PLACED: Ticket #" + IntegerToString((int)g_trade.ResultOrder()));
     }
  }

//+------------------------------------------------------------------+
//| MANAGE OPEN POSITIONS                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_position.SelectByIndex(i))
         continue;
      if(g_position.Symbol() != Symbol() || g_position.Magic() != InpMagicNumber)
         continue;

      double openPrice  = g_position.PriceOpen();
      double currentSL  = g_position.StopLoss();
      double currentTP  = g_position.TakeProfit();
      double profit     = g_position.Profit();
      double volume     = g_position.Volume();
      ulong  ticket     = g_position.Ticket();

      // Calculate initial risk (1R)
      double initialRisk = MathAbs(openPrice - currentSL);
      if(initialRisk <= 0)
         continue;

      double currentPrice;
      double priceDelta;

      if(g_position.PositionType() == POSITION_TYPE_BUY)
        {
         currentPrice = g_symbol.Bid();
         priceDelta   = currentPrice - openPrice;
        }
      else
        {
         currentPrice = g_symbol.Ask();
         priceDelta   = openPrice - currentPrice;
        }

      double rMultiple = priceDelta / initialRisk;

      // ── Break-even at 1R ──
      if(InpUseBreakeven && rMultiple >= 1.0)
        {
         double beLevel;
         if(g_position.PositionType() == POSITION_TYPE_BUY)
            beLevel = openPrice + g_symbol.Spread() * g_symbol.Point();
         else
            beLevel = openPrice - g_symbol.Spread() * g_symbol.Point();

         beLevel = NormalizeDouble(beLevel, (int)g_symbol.Digits());

         if(g_position.PositionType() == POSITION_TYPE_BUY && currentSL < beLevel)
           {
            g_trade.PositionModify(ticket, beLevel, currentTP);
            DebugLog("Break-even set for BUY #" + IntegerToString((int)ticket));
           }
         else if(g_position.PositionType() == POSITION_TYPE_SELL && (currentSL > beLevel || currentSL == 0))
           {
            g_trade.PositionModify(ticket, beLevel, currentTP);
            DebugLog("Break-even set for SELL #" + IntegerToString((int)ticket));
           }
        }

      // ── Partial Close 50% at 1.5R ──
      if(InpUsePartialClose && rMultiple >= 1.5)
        {
         // Parse comment to check if already partially closed
         string comment = g_position.Comment();
         if(StringFind(comment, "PC") < 0 && volume > g_symbol.LotsMin())
           {
            double closeVol = MathFloor((volume * 0.5) / g_symbol.LotsStep()) * g_symbol.LotsStep();
            if(closeVol >= g_symbol.LotsMin())
              {
               g_trade.PositionClosePartial(ticket, closeVol);
               DebugLog("Partial close 50% for #" + IntegerToString((int)ticket) +
                        " | Closed: " + DoubleToString(closeVol, 2));
               // Note: We can't modify comment on partial, but the volume change tracks it
              }
           }
        }

      // ── Trailing Stop (ATR-based) ──
      if(InpUseTrailingStop && rMultiple >= 1.0 && g_currentATR > 0)
        {
         double trailDist = g_currentATR * InpTrailingATRMult;
         double newSL;

         if(g_position.PositionType() == POSITION_TYPE_BUY)
           {
            newSL = NormalizeDouble(currentPrice - trailDist, (int)g_symbol.Digits());
            if(newSL > currentSL && newSL < currentPrice)
              {
               g_trade.PositionModify(ticket, newSL, currentTP);
              }
           }
         else
           {
            newSL = NormalizeDouble(currentPrice + trailDist, (int)g_symbol.Digits());
            if((newSL < currentSL || currentSL == 0) && newSL > currentPrice)
              {
               g_trade.PositionModify(ticket, newSL, currentTP);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| ADAPTIVE LEARNING                                                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   // Only process deal additions (closed trades)
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   // Check if it's our trade closing
   if(trans.deal_type != DEAL_TYPE_BUY && trans.deal_type != DEAL_TYPE_SELL)
      return;

   // Get deal info
   if(!HistoryDealSelect(trans.deal))
      return;

   long dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(dealMagic != InpMagicNumber)
      return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return;

   double dealProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   double dealSwap   = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
   double dealComm   = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   double netPnl     = dealProfit + dealSwap + dealComm;

   // Parse score from comment
   string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   double tradeScore = ParseScoreFromComment(comment);

   // Record trade
   TradeRecord rec;
   rec.score = tradeScore;
   rec.pnl   = netPnl;
   rec.isWin = (netPnl > 0);
   rec.mode  = g_activeMode;

   // Add to history (keep last 50)
   int size = ArraySize(g_tradeHistory);
   if(size >= 50)
     {
      // Shift left
      for(int i = 0; i < size - 1; i++)
         g_tradeHistory[i] = g_tradeHistory[i + 1];
      g_tradeHistory[size - 1] = rec;
     }
   else
     {
      ArrayResize(g_tradeHistory, size + 1);
      g_tradeHistory[size] = rec;
     }
   g_historyCount = ArraySize(g_tradeHistory);

   // Update consecutive wins
   if(netPnl > 0)
      g_consecutiveWins++;
   else
      g_consecutiveWins = 0;

   // ── Adaptive Logic ──
   AdaptiveUpdate();

   DebugLog("TRADE CLOSED: PnL=" + DoubleToString(netPnl, 2) +
            " | Score=" + DoubleToString(tradeScore, 3) +
            " | ConsecWins=" + IntegerToString(g_consecutiveWins) +
            " | AdaptiveThresh=" + DoubleToString(g_adaptiveThreshold, 3) +
            " | AdaptiveLotMult=" + DoubleToString(g_adaptiveLotMult, 3));
  }

double ParseScoreFromComment(string comment)
  {
   // Format: "GMSE|MODE_XXX|S0.85"
   int pos = StringFind(comment, "|S");
   if(pos < 0)
      return 0.7; // default
   string scoreStr = StringSubstr(comment, pos + 2);
   return StringToDouble(scoreStr);
  }

void AdaptiveUpdate()
  {
   if(g_historyCount < 10)
      return;

   // Count wins/losses for low-score and high-score trades
   int lowScoreLoss = 0, lowScoreTotal = 0;
   int highScoreWin = 0, highScoreTotal = 0;

   double medianScore = InpMinScore;

   for(int i = 0; i < g_historyCount; i++)
     {
      if(g_tradeHistory[i].score < medianScore + 0.1)
        {
         lowScoreTotal++;
         if(!g_tradeHistory[i].isWin)
            lowScoreLoss++;
        }
      else
        {
         highScoreTotal++;
         if(g_tradeHistory[i].isWin)
            highScoreWin++;
        }
     }

   // If low-score trades losing → increase threshold
   if(lowScoreTotal > 3)
     {
      double lossRate = (double)lowScoreLoss / (double)lowScoreTotal;
      if(lossRate > 0.6)
         g_adaptiveThreshold = MathMin(g_adaptiveThreshold + 0.02, 0.15);
      else if(lossRate < 0.4)
         g_adaptiveThreshold = MathMax(g_adaptiveThreshold - 0.01, 0.0);
     }

   // If high-score trades winning → slightly increase lot
   if(highScoreTotal > 3)
     {
      double winRate = (double)highScoreWin / (double)highScoreTotal;
      if(winRate > 0.65)
         g_adaptiveLotMult = MathMin(g_adaptiveLotMult + 0.05, 1.3);
      else if(winRate < 0.4)
         g_adaptiveLotMult = MathMax(g_adaptiveLotMult - 0.05, 0.7);
     }

   // ── Reduce weight of weak signals ──
   // Calculate win rate per factor (approximate via score correlation)
   UpdateSignalWeights();
  }

void UpdateSignalWeights()
  {
   // Simple approach: if recent trades are mostly losers, slightly shift weights
   // toward structure and liquidity (most reliable) and away from volume/volatility
   if(g_historyCount < 20)
      return;

   int recentWins = 0;
   int recentCount = MathMin(20, g_historyCount);
   for(int i = g_historyCount - recentCount; i < g_historyCount; i++)
     {
      if(g_tradeHistory[i].isWin)
         recentWins++;
     }

   double winRate = (double)recentWins / (double)recentCount;

   if(winRate < 0.4)
     {
      // Shift toward structure/liquidity (more conservative)
      g_wStructure  = MathMin(0.35, g_wStructure + 0.01);
      g_wLiquidity  = MathMin(0.30, g_wLiquidity + 0.01);
      g_wVolume     = MathMax(0.10, g_wVolume - 0.01);
      g_wVolatility = MathMax(0.05, g_wVolatility - 0.005);
      g_wEntry      = MathMax(0.10, g_wEntry - 0.005);
     }
   else if(winRate > 0.6)
     {
      // Revert toward default
      g_wStructure  = g_wStructure  + (InpWeightStructure  - g_wStructure) * 0.1;
      g_wLiquidity  = g_wLiquidity  + (InpWeightLiquidity  - g_wLiquidity) * 0.1;
      g_wVolume     = g_wVolume     + (InpWeightVolume     - g_wVolume) * 0.1;
      g_wVolatility = g_wVolatility + (InpWeightVolatility - g_wVolatility) * 0.1;
      g_wEntry      = g_wEntry      + (InpWeightEntry      - g_wEntry) * 0.1;
     }

   // Normalize weights to sum to 1
   double total = g_wStructure + g_wLiquidity + g_wVolume + g_wVolatility + g_wEntry;
   if(total > 0)
     {
      g_wStructure  /= total;
      g_wLiquidity  /= total;
      g_wVolume     /= total;
      g_wVolatility /= total;
      g_wEntry      /= total;
     }
  }

//+------------------------------------------------------------------+
//| OnTimer - for periodic operations                                |
//+------------------------------------------------------------------+
void OnTimer()
  {
   // Reserved for future use (e.g., periodic state logging)
  }
//+------------------------------------------------------------------+
