#property strict
#property indicator_separate_window
#property indicator_minimum 0
#property indicator_maximum 100
#property indicator_buffers 6
#property indicator_color1 DeepSkyBlue
#property indicator_color2 Orange
#property indicator_color3 LimeGreen
#property indicator_color4 Tomato
#property indicator_color5 clrNONE
#property indicator_color6 clrNONE

input int    InpKPeriod            = 5;
input int    InpDPeriod            = 3;
input int    InpSlowing            = 3;
input int    InpATRPeriod          = 14;
input int    InpFastEMA            = 21;
input int    InpSlowEMA            = 55;
input double InpImpulseATRMult     = 1.20;
input double InpRetraceATRMult     = 0.70;
input double InpCompressionFactor  = 0.75;
input double InpEMASepATRMult      = 0.10;
input double InpEMASlopeATRMult    = 0.05;
input double InpStochImpulse       = 18.0;
input double InpStochRetrace       = 10.0;
input int    InpABCMaxBarGap       = 8;
input double InpEqualAtrMult       = 0.20;
input double InpSweepAtrMult       = 0.05;
input bool   InpEnableB1B2         = true;
input bool   InpEnableC1C2         = true;
input double InpOrderblockHigh     = 0.0;
input double InpOrderblockLow      = 0.0;
input double InpSupplyZone         = 0.0;
input double InpDemandZone         = 0.0;
input double InpZoneAtrMult        = 0.30;
input bool   InpEnableAlerts       = true;
input bool   InpDebugLogs          = true;

// plotted buffers
double StochMainBuffer[];
double StochSignalBuffer[];
double StochSwingHighBuffer[];
double StochSwingLowBuffer[];
// internal state
double PriceSwingHighState[];
double PriceSwingLowState[];

string PREFIX = "PSD_DIV_MT4_";
datetime gLastBarTime = 0;
string gLastAlertKey = "";
datetime gLastAlertWhen = 0;

void Dbg(string s){ if(InpDebugLogs) Print("[DEBUG][MT4] ",s); }

string TfStr(){ return(IntegerToString(Period())); }

void ResetWorkingBuffers(int total)
{
   for(int i=0;i<total;i++)
   {
      StochSwingHighBuffer[i]=EMPTY_VALUE;
      StochSwingLowBuffer[i]=EMPTY_VALUE;
      PriceSwingHighState[i]=EMPTY_VALUE;
      PriceSwingLowState[i]=EMPTY_VALUE;
   }
}

void EvaluatePriceStructure(const int total,const double &high[],const double &low[],const double &close[])
{
   int start=total-2,dir=0,extBar=start;
   double ext=close[start],legStart=close[start];
   for(int i=start;i>=1;i--)
   {
      double atr=iATR(NULL,0,InpATRPeriod,i); if(atr<=0) continue;
      double atrAvg=0; int n=0; for(n=0;n<10 && i+n<total;n++) atrAvg+=iATR(NULL,0,InpATRPeriod,i+n); if(n>0) atrAvg/=n;
      double emaFast=iMA(NULL,0,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,i);
      double emaSlow=iMA(NULL,0,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,i);
      double emaFastPrev=iMA(NULL,0,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,i+1);
      bool compressed=(atrAvg>0 && atr<atrAvg*InpCompressionFactor);
      bool emaQualified=(MathAbs(emaFast-emaSlow)>=atr*InpEMASepATRMult || MathAbs(emaFast-emaFastPrev)>=atr*InpEMASlopeATRMult);
      if(dir==0)
      {
         legStart=close[i+1]; ext=close[i+1]; extBar=i+1;
         if(!compressed && emaQualified)
         {
            if(close[i]-legStart>=atr*InpImpulseATRMult){dir=1; ext=high[i]; extBar=i;}
            else if(legStart-close[i]>=atr*InpImpulseATRMult){dir=-1; ext=low[i]; extBar=i;}
         }
      }
      else if(dir==1)
      {
         if(high[i]>ext){ext=high[i]; extBar=i;}
         if(ext-low[i]>=atr*InpRetraceATRMult){PriceSwingHighState[extBar]=high[extBar]; dir=-1; legStart=ext; ext=low[i]; extBar=i;}
      }
      else
      {
         if(low[i]<ext){ext=low[i]; extBar=i;}
         if(high[i]-ext>=atr*InpRetraceATRMult){PriceSwingLowState[extBar]=low[extBar]; dir=1; legStart=ext; ext=high[i]; extBar=i;}
      }
   }
}

void EvaluateStochStructure(const int total)
{
   int start=total-2,dir=0,extBar=start;
   double ext=StochMainBuffer[start],legStart=StochMainBuffer[start];
   for(int i=start;i>=1;i--)
   {
      double sv=StochMainBuffer[i],sp=StochMainBuffer[i+1];
      if(dir==0)
      {
         legStart=sp; ext=sp; extBar=i+1;
         if(sv-legStart>=InpStochImpulse){dir=1; ext=sv; extBar=i;}
         else if(legStart-sv>=InpStochImpulse){dir=-1; ext=sv; extBar=i;}
      }
      else if(dir==1)
      {
         if(sv>ext){ext=sv; extBar=i;}
         if(ext-sv>=InpStochRetrace){StochSwingHighBuffer[extBar]=ext; dir=-1; legStart=ext; ext=sv; extBar=i;}
      }
      else
      {
         if(sv<ext){ext=sv; extBar=i;}
         if(sv-ext>=InpStochRetrace){StochSwingLowBuffer[extBar]=ext; dir=1; legStart=ext; ext=sv; extBar=i;}
      }
   }
}

void CollectPoints(const int total,const double &highBuf[],const double &lowBuf[],int &bars[],double &vals[],int &types[])
{
   ArrayResize(bars,0); ArrayResize(vals,0); ArrayResize(types,0);
   for(int i=total-2;i>=1;i--)
   {
      bool h=(highBuf[i]!=EMPTY_VALUE), l=(lowBuf[i]!=EMPTY_VALUE);
      if(!h && !l) continue;
      int ns=ArraySize(bars)+1;
      ArrayResize(bars,ns); ArrayResize(vals,ns); ArrayResize(types,ns);
      bars[ns-1]=i; vals[ns-1]=(h?highBuf[i]:lowBuf[i]); types[ns-1]=(h?1:-1);
   }
}

bool NearestByBar(const int &bars[],const double &vals[],int target,int maxGap,int &outBar,double &outVal)
{
   int best=-1,bestGap=100000;
   for(int i=0;i<ArraySize(bars);i++)
   {
      int g=MathAbs(bars[i]-target);
      if(g<bestGap && g<=maxGap){best=i; bestGap=g;}
   }
   if(best<0) return(false);
   outBar=bars[best]; outVal=vals[best]; return(true);
}

void ClearDivObjects()
{
   string names[]={"P1","P2","S1","S2","LA","LB","LC","SA","SB","SC","NAME"};
   for(int i=0;i<ArraySize(names);i++) ObjectDelete(PREFIX+names[i]);
}

void DrawTrend(string name,int wnd,datetime t1,double p1,datetime t2,double p2,color c)
{
   ObjectDelete(name);
   ObjectCreate(name,OBJ_TREND,wnd,t1,p1,t2,p2);
   ObjectSet(name,OBJPROP_COLOR,c); ObjectSet(name,OBJPROP_WIDTH,2); ObjectSet(name,OBJPROP_RAY,false);
}

void DrawTxt(string name,int wnd,datetime t,double p,string txt,color c)
{
   ObjectDelete(name); ObjectCreate(name,OBJ_TEXT,wnd,t,p); ObjectSetText(name,txt,9,"Arial",c);
}

void AlertDivergence(string code,string label,bool bull,string trig,datetime barTime)
{
   if(!InpEnableAlerts) return;
   string key=Symbol()+"|"+TfStr()+"|"+code+"|"+TimeToString(barTime,TIME_DATE|TIME_MINUTES);
   if(key==gLastAlertKey || gLastAlertWhen==barTime) return;
   string msg=StringFormat("%s %s %s %s trigger=%s",Symbol(),TfStr(),code,(bull?"BULLISH":"BEARISH"),trig);
   Alert(msg); Print("[ALERT][MT4] ",msg);
   gLastAlertKey=key; gLastAlertWhen=barTime;
}

// returns true when detected and fills fields
bool DetectAndRender(const int total,const datetime &time[],const double &high[],const double &low[])
{
   int pBars[],pTypes[],sBars[],sTypes[]; double pVals[],sVals[];
   int phBars[],phTypes[],plBars[],plTypes[],shBars[],shTypes[],slBars[],slTypes[];
   double phVals[],plVals[],shVals[],slVals[];

   CollectPoints(total,PriceSwingHighState,PriceSwingLowState,pBars,pVals,pTypes);
   CollectPoints(total,StochSwingHighBuffer,StochSwingLowBuffer,sBars,sVals,sTypes);
   CollectPoints(total,PriceSwingHighState,PriceSwingLowState,phBars,phVals,phTypes);
   CollectPoints(total,StochSwingHighBuffer,StochSwingLowBuffer,shBars,shVals,shTypes);
   CollectPoints(total,PriceSwingLowState,PriceSwingHighState,plBars,plVals,plTypes); // lows only via type=-1 after swap
   CollectPoints(total,StochSwingLowBuffer,StochSwingHighBuffer,slBars,slVals,slTypes);

   // keep only highs/lows explicitly
   int tphB[]; double tphV[]; int tslB[]; double tslV[];
   ArrayResize(tphB,0); ArrayResize(tphV,0); ArrayResize(tslB,0); ArrayResize(tslV,0);
   for(int i=0;i<ArraySize(pBars);i++) if(pTypes[i]==1){int n=ArraySize(tphB)+1;ArrayResize(tphB,n);ArrayResize(tphV,n);tphB[n-1]=pBars[i];tphV[n-1]=pVals[i];}
   int tplB[]; double tplV[]; int tshB[]; double tshV[];
   ArrayResize(tplB,0); ArrayResize(tplV,0); ArrayResize(tshB,0); ArrayResize(tshV,0);
   for(int i=0;i<ArraySize(pBars);i++) if(pTypes[i]==-1){int n=ArraySize(tplB)+1;ArrayResize(tplB,n);ArrayResize(tplV,n);tplB[n-1]=pBars[i];tplV[n-1]=pVals[i];}
   for(int i=0;i<ArraySize(sBars);i++) if(sTypes[i]==1){int n=ArraySize(tshB)+1;ArrayResize(tshB,n);ArrayResize(tshV,n);tshB[n-1]=sBars[i];tshV[n-1]=sVals[i];}
   for(int i=0;i<ArraySize(sBars);i++) if(sTypes[i]==-1){int n=ArraySize(tslB)+1;ArrayResize(tslB,n);ArrayResize(tslV,n);tslB[n-1]=sBars[i];tslV[n-1]=sVals[i];}

   if(ArraySize(tphB)<2 || ArraySize(tplB)<2 || ArraySize(tshB)<2 || ArraySize(tslB)<2){ ClearDivObjects(); return(false); }

   double atr=iATR(NULL,0,InpATRPeriod,1); if(atr<=0) atr=Point*100;
   double eqTol=atr*InpEqualAtrMult, sweepTol=atr*InpSweepAtrMult, zoneTol=atr*InpZoneAtrMult;

   string code="",name="",trigger="B"; bool bull=false; bool is3=false;
   int pA=-1,pB=-1,pC=-1,sA=-1,sB=-1,sC=-1; double pvA=0,pvB=0,pvC=0,svA=0,svB=0,svC=0;

   // A1/E1 from highs (3D bearish) priority to A1 sweep
   if(ArraySize(tphB)>=3)
   {
      int n=ArraySize(tphB);
      pA=tphB[n-3]; pB=tphB[n-2]; pC=tphB[n-1]; pvA=tphV[n-3]; pvB=tphV[n-2]; pvC=tphV[n-1];
      bool gotA=NearestByBar(tshB,tshV,pA,InpABCMaxBarGap,sA,svA);
      bool gotB=NearestByBar(tshB,tshV,pB,InpABCMaxBarGap,sB,svB);
      bool gotC=NearestByBar(tshB,tshV,pC,InpABCMaxBarGap,sC,svC);
      if(gotA&&gotB&&gotC)
      {
         bool sweep=(MathAbs(pvA-pvB)<=eqTol && pvC>MathMax(pvA,pvB)+sweepTol && svC<MathMax(svA,svB));
         bool normal=(pvC>pvA+sweepTol && svC<svA);
         if(sweep){code="A1";name="A1 BSL SWEEP 3D BEARISH";bull=false;is3=true;trigger="C";}
         else if(normal){code="E1";name="E1 3D NORMAL BEARISH";bull=false;is3=true;trigger="C";}
      }
   }

   // A2/E2 from lows (3D bullish)
   if(code=="" && ArraySize(tplB)>=3)
   {
      int n=ArraySize(tplB);
      pA=tplB[n-3]; pB=tplB[n-2]; pC=tplB[n-1]; pvA=tplV[n-3]; pvB=tplV[n-2]; pvC=tplV[n-1];
      bool gotA=NearestByBar(tslB,tslV,pA,InpABCMaxBarGap,sA,svA);
      bool gotB=NearestByBar(tslB,tslV,pB,InpABCMaxBarGap,sB,svB);
      bool gotC=NearestByBar(tslB,tslV,pC,InpABCMaxBarGap,sC,svC);
      if(gotA&&gotB&&gotC)
      {
         bool sweep=(MathAbs(pvA-pvB)<=eqTol && pvC<MathMin(pvA,pvB)-sweepTol && svC>MathMin(svA,svB));
         bool normal=(pvC<pvA-sweepTol && svC>svA);
         if(sweep){code="A2";name="A2 SSL SWEEP 3D BULLISH";bull=true;is3=true;trigger="C";}
         else if(normal){code="E2";name="E2 3D NORMAL BULLISH";bull=true;is3=true;trigger="C";}
      }
   }

   // 2D highs (A3/D1/B1/C1)
   if(code=="" && ArraySize(tphB)>=2)
   {
      int n=ArraySize(tphB);
      pA=tphB[n-2]; pB=tphB[n-1]; pvA=tphV[n-2]; pvB=tphV[n-1]; pC=-1;
      bool gotA=NearestByBar(tshB,tshV,pA,InpABCMaxBarGap,sA,svA);
      bool gotB=NearestByBar(tshB,tshV,pB,InpABCMaxBarGap,sB,svB);
      if(gotA&&gotB && pvB>pvA+sweepTol && svB<svA)
      {
         if(MathAbs(pvA-pvB)<=eqTol+sweepTol){code="A3";name="A3 BSL SWEEP 2D BEARISH";}
         else {code="D1";name="D1 2D NORMAL BEARISH";}
         bull=false; is3=false; trigger="B";
         if(InpEnableB1B2 && InpOrderblockHigh>0 && MathAbs(pvB-InpOrderblockHigh)<=zoneTol){code="B1";name="B1 OB RETURN 2D BEARISH";}
         if(InpEnableC1C2 && InpSupplyZone>0 && MathAbs(pvB-InpSupplyZone)<=zoneTol){code="C1";name="C1 SUPPLY RETURN 2D BEARISH";}
      }
   }

   // 2D lows (A4/D2/B2/C2)
   if(code=="" && ArraySize(tplB)>=2)
   {
      int n=ArraySize(tplB);
      pA=tplB[n-2]; pB=tplB[n-1]; pvA=tplV[n-2]; pvB=tplV[n-1]; pC=-1;
      bool gotA=NearestByBar(tslB,tslV,pA,InpABCMaxBarGap,sA,svA);
      bool gotB=NearestByBar(tslB,tslV,pB,InpABCMaxBarGap,sB,svB);
      if(gotA&&gotB && pvB<pvA-sweepTol && svB>svA)
      {
         if(MathAbs(pvA-pvB)<=eqTol+sweepTol){code="A4";name="A4 SSL SWEEP 2D BULLISH";}
         else {code="D2";name="D2 2D NORMAL BULLISH";}
         bull=true; is3=false; trigger="B";
         if(InpEnableB1B2 && InpOrderblockLow>0 && MathAbs(pvB-InpOrderblockLow)<=zoneTol){code="B2";name="B2 OB RETURN 2D BULLISH";}
         if(InpEnableC1C2 && InpDemandZone>0 && MathAbs(pvB-InpDemandZone)<=zoneTol){code="C2";name="C2 DEMAND RETURN 2D BULLISH";}
      }
   }

   if(code==""){ ClearDivObjects(); return(false); }

   // draw
   ClearDivObjects();
   int compBar=(trigger=="C"?pC:pB);
   DrawTrend(PREFIX+"P1",0,time[pA],pvA,time[(trigger=="C"?pC:pB)],(trigger=="C"?pvC:pvB),bull?clrLime:clrRed);
   DrawTrend(PREFIX+"S1",1,time[sA],svA,time[(trigger=="C"?sC:sB)],(trigger=="C"?svC:svB),bull?clrLime:clrRed);
   DrawTxt(PREFIX+"LA",0,time[pA],pvA,"A",clrWhite);
   DrawTxt(PREFIX+"LB",0,time[pB],pvB,"B",clrWhite);
   DrawTxt(PREFIX+"SA",1,time[sA],svA,"A",clrWhite);
   DrawTxt(PREFIX+"SB",1,time[sB],svB,"B",clrWhite);
   if(is3)
   {
      DrawTrend(PREFIX+"P2",0,time[pB],pvB,time[pC],pvC,bull?clrLime:clrRed);
      DrawTrend(PREFIX+"S2",1,time[sB],svB,time[sC],svC,bull?clrLime:clrRed);
      DrawTxt(PREFIX+"LC",0,time[pC],pvC,"C",clrWhite);
      DrawTxt(PREFIX+"SC",1,time[sC],svC,"C",clrWhite);
   }
   DrawTxt(PREFIX+"NAME",0,time[compBar],(bull?low[compBar]:high[compBar]),name,bull?clrLime:clrRed);

   // early alert on current chart timeframe only and only fresh close of trigger point
   if(compBar==1) AlertDivergence(code,name,bull,trigger,time[1]);
   return(true);
}

int OnInit()
{
   Dbg("[OnInit] Start");
   IndicatorShortName("Professional Structural Stoch Divergence - Stage2+3 (MT4)");
   SetIndexBuffer(0,StochMainBuffer); SetIndexStyle(0,DRAW_LINE,STYLE_SOLID,1,clrDeepSkyBlue); SetIndexLabel(0,"Stoch Main");
   SetIndexBuffer(1,StochSignalBuffer); SetIndexStyle(1,DRAW_LINE,STYLE_SOLID,1,clrOrange); SetIndexLabel(1,"Stoch Signal");
   SetIndexBuffer(2,StochSwingHighBuffer); SetIndexStyle(2,DRAW_ARROW,STYLE_SOLID,1,clrLimeGreen); SetIndexArrow(2,159); SetIndexLabel(2,"Stoch Swing High");
   SetIndexBuffer(3,StochSwingLowBuffer); SetIndexStyle(3,DRAW_ARROW,STYLE_SOLID,1,clrTomato); SetIndexArrow(3,159); SetIndexLabel(3,"Stoch Swing Low");
   SetIndexBuffer(4,PriceSwingHighState); SetIndexStyle(4,DRAW_NONE);
   SetIndexBuffer(5,PriceSwingLowState); SetIndexStyle(5,DRAW_NONE);
   SetIndexEmptyValue(2,EMPTY_VALUE); SetIndexEmptyValue(3,EMPTY_VALUE);
   Dbg("[OnInit] After buffers");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){ ClearDivObjects(); }

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
{
   int minBars=MathMax(MathMax(InpSlowEMA,InpATRPeriod),InpKPeriod+InpDPeriod+InpSlowing)+20;
   if(rates_total<minBars){ Dbg("[OnCalculate] early exit rates_total="+IntegerToString(rates_total)); return(0);}   

   for(int i=0;i<rates_total;i++)
   {
      StochMainBuffer[i]=iStochastic(NULL,0,InpKPeriod,InpDPeriod,InpSlowing,MODE_SMA,0,MODE_MAIN,i);
      StochSignalBuffer[i]=iStochastic(NULL,0,InpKPeriod,InpDPeriod,InpSlowing,MODE_SMA,0,MODE_SIGNAL,i);
   }

   ResetWorkingBuffers(rates_total);
   EvaluatePriceStructure(rates_total,high,low,close);
   EvaluateStochStructure(rates_total);
   DetectAndRender(rates_total,time,high,low);

   gLastBarTime=time[0];
   return(rates_total);
}
