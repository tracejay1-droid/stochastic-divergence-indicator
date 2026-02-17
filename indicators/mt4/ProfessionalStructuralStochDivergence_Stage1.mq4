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

double StochMainBuffer[];
double StochSignalBuffer[];
double StochSwingHighBuffer[];
double StochSwingLowBuffer[];
double PriceSwingHighState[];
double PriceSwingLowState[];

string PREFIX = "PSD_DIV_MT4_";
string IND_SHORTNAME = "Professional Structural Stoch Divergence - Stage2+3 (MT4)";
string gLastAlertKey = "";
datetime gLastAlertWhen = 0;
datetime gLastStatsBar = 0;

void Dbg(string s){ if(InpDebugLogs) Print("[DEBUG][MT4] ",s); }
string TfStr(){ return(IntegerToString(Period())); }

int GetSubwindow(){ int w=WindowFind(IND_SHORTNAME); if(w<1) w=1; return(w); }

void ResetWorkingBuffers(int total){ for(int i=0;i<total;i++){StochSwingHighBuffer[i]=EMPTY_VALUE;StochSwingLowBuffer[i]=EMPTY_VALUE;PriceSwingHighState[i]=EMPTY_VALUE;PriceSwingLowState[i]=EMPTY_VALUE;}}

void EvaluatePriceStructure(const int total,const double &high[],const double &low[],const double &close[])
{
   int start=total-2,dir=0,extBar=start; double ext=close[start],legStart=close[start];
   for(int i=start;i>=1;i--)
   {
      double atr=iATR(NULL,0,InpATRPeriod,i); if(atr<=0) continue;
      double atrAvg=0; int n=0; for(n=0;n<10 && i+n<total;n++) atrAvg+=iATR(NULL,0,InpATRPeriod,i+n); if(n>0) atrAvg/=n;
      double emaFast=iMA(NULL,0,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,i);
      double emaSlow=iMA(NULL,0,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,i);
      double emaFastPrev=iMA(NULL,0,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,i+1);
      bool compressed=(atrAvg>0 && atr<atrAvg*InpCompressionFactor);
      bool emaQualified=(MathAbs(emaFast-emaSlow)>=atr*InpEMASepATRMult || MathAbs(emaFast-emaFastPrev)>=atr*InpEMASlopeATRMult);
      if(dir==0){legStart=close[i+1]; ext=close[i+1]; extBar=i+1; if(!compressed && emaQualified){if(close[i]-legStart>=atr*InpImpulseATRMult){dir=1; ext=high[i]; extBar=i;} else if(legStart-close[i]>=atr*InpImpulseATRMult){dir=-1; ext=low[i]; extBar=i;}}}
      else if(dir==1){if(high[i]>ext){ext=high[i]; extBar=i;} if(ext-low[i]>=atr*InpRetraceATRMult){PriceSwingHighState[extBar]=high[extBar]; dir=-1; legStart=ext; ext=low[i]; extBar=i;}}
      else {if(low[i]<ext){ext=low[i]; extBar=i;} if(high[i]-ext>=atr*InpRetraceATRMult){PriceSwingLowState[extBar]=low[extBar]; dir=1; legStart=ext; ext=high[i]; extBar=i;}}
   }
}

void EvaluateStochStructure(const int total)
{
   int start=total-2,dir=0,extBar=start; double ext=StochMainBuffer[start],legStart=StochMainBuffer[start];
   for(int i=start;i>=1;i--)
   {
      double sv=StochMainBuffer[i],sp=StochMainBuffer[i+1];
      if(dir==0){legStart=sp; ext=sp; extBar=i+1; if(sv-legStart>=InpStochImpulse){dir=1; ext=sv; extBar=i;} else if(legStart-sv>=InpStochImpulse){dir=-1; ext=sv; extBar=i;}}
      else if(dir==1){if(sv>ext){ext=sv; extBar=i;} if(ext-sv>=InpStochRetrace){StochSwingHighBuffer[extBar]=ext; dir=-1; legStart=ext; ext=sv; extBar=i;}}
      else {if(sv<ext){ext=sv; extBar=i;} if(sv-ext>=InpStochRetrace){StochSwingLowBuffer[extBar]=ext; dir=1; legStart=ext; ext=sv; extBar=i;}}
   }
}

void CollectPoints(const int total,const double &highBuf[],const double &lowBuf[],int &bars[],double &vals[],int &types[])
{
   ArrayResize(bars,0); ArrayResize(vals,0); ArrayResize(types,0);
   for(int i=total-2;i>=1;i--)
   {
      bool h=(highBuf[i]!=EMPTY_VALUE), l=(lowBuf[i]!=EMPTY_VALUE); if(!h && !l) continue;
      int ns=ArraySize(bars)+1; ArrayResize(bars,ns); ArrayResize(vals,ns); ArrayResize(types,ns);
      bars[ns-1]=i; vals[ns-1]=(h?highBuf[i]:lowBuf[i]); types[ns-1]=(h?1:-1);
   }
}

bool NearestByBar(const int &bars[],const double &vals[],int target,int maxGap,int &outBar,double &outVal)
{
   int best=-1,bg=100000;
   for(int i=0;i<ArraySize(bars);i++){int g=MathAbs(bars[i]-target); if(g<bg && g<=maxGap){bg=g; best=i;}}
   if(best<0) return(false); outBar=bars[best]; outVal=vals[best]; return(true);
}

void ClearDivObjects(){ string names[]={"P1","P2","S1","S2","LA","LB","LC","SA","SB","SC","NAME"}; for(int i=0;i<ArraySize(names);i++) ObjectDelete(PREFIX+names[i]); }
void DrawTrend(string name,int wnd,datetime t1,double p1,datetime t2,double p2,color c){ObjectDelete(name); ObjectCreate(name,OBJ_TREND,wnd,t1,p1,t2,p2); ObjectSet(name,OBJPROP_COLOR,c); ObjectSet(name,OBJPROP_WIDTH,2); ObjectSet(name,OBJPROP_RAY,false);} 
void DrawTxt(string name,int wnd,datetime t,double p,string txt,color c){ObjectDelete(name); ObjectCreate(name,OBJ_TEXT,wnd,t,p); ObjectSetText(name,txt,9,"Arial",c);} 

void AlertDivergence(string code,bool bull,string trig,datetime barTime)
{
   if(!InpEnableAlerts) return;
   string key=Symbol()+"|"+TfStr()+"|"+code+"|"+TimeToString(barTime,TIME_DATE|TIME_MINUTES);
   if(key==gLastAlertKey || gLastAlertWhen==barTime) return;
   string msg=StringFormat("%s|%s|%s|%s|Trigger=%s|%s",Symbol(),TfStr(),code,(bull?"BULLISH":"BEARISH"),trig,TimeToString(barTime,TIME_DATE|TIME_MINUTES));
   Alert(msg); Print("[ALERT][MT4] ",msg); gLastAlertKey=key; gLastAlertWhen=barTime;
}

bool DetectAndRender(const int total,const datetime &time[],const double &high[],const double &low[],int &candCount,int &confCount)
{
   int pBars[],pTypes[],sBars[],sTypes[]; double pVals[],sVals[];
   CollectPoints(total,PriceSwingHighState,PriceSwingLowState,pBars,pVals,pTypes);
   CollectPoints(total,StochSwingHighBuffer,StochSwingLowBuffer,sBars,sVals,sTypes);

   int phB[],plB[],shB[],slB[]; double phV[],plV[],shV[],slV[];
   ArrayResize(phB,0);ArrayResize(plB,0);ArrayResize(shB,0);ArrayResize(slB,0);
   ArrayResize(phV,0);ArrayResize(plV,0);ArrayResize(shV,0);ArrayResize(slV,0);
   for(int i=0;i<ArraySize(pBars);i++) if(pTypes[i]==1){int n=ArraySize(phB)+1;ArrayResize(phB,n);ArrayResize(phV,n);phB[n-1]=pBars[i];phV[n-1]=pVals[i];} else {int n2=ArraySize(plB)+1;ArrayResize(plB,n2);ArrayResize(plV,n2);plB[n2-1]=pBars[i];plV[n2-1]=pVals[i];}
   for(int i=0;i<ArraySize(sBars);i++) if(sTypes[i]==1){int n=ArraySize(shB)+1;ArrayResize(shB,n);ArrayResize(shV,n);shB[n-1]=sBars[i];shV[n-1]=sVals[i];} else {int n2=ArraySize(slB)+1;ArrayResize(slB,n2);ArrayResize(slV,n2);slB[n2-1]=sBars[i];slV[n2-1]=sVals[i];}
   if(ArraySize(phB)<2 || ArraySize(plB)<2 || ArraySize(shB)<2 || ArraySize(slB)<2){ClearDivObjects(); return(false);}   

   double atr=iATR(NULL,0,InpATRPeriod,1); if(atr<=0) atr=Point*100;
   double eqTol=atr*InpEqualAtrMult, sweepTol=atr*InpSweepAtrMult, zoneTol=atr*InpZoneAtrMult;
   string code="",name="",trigger="B"; bool bull=false,is3=false;
   int pA=-1,pB=-1,pC=-1,sA=-1,sB=-1,sC=-1; double pvA=0,pvB=0,pvC=0,svA=0,svB=0,svC=0;

   if(ArraySize(phB)>=3)
   {
      candCount++;
      int n=ArraySize(phB); pA=phB[n-3];pB=phB[n-2];pC=phB[n-1]; pvA=phV[n-3];pvB=phV[n-2];pvC=phV[n-1];
      bool ga=NearestByBar(shB,shV,pA,InpABCMaxBarGap,sA,svA), gb=NearestByBar(shB,shV,pB,InpABCMaxBarGap,sB,svB), gc=NearestByBar(shB,shV,pC,InpABCMaxBarGap,sC,svC);
      if(ga&&gb&&gc){ bool sweep=(MathAbs(pvA-pvB)<=eqTol && pvC>MathMax(pvA,pvB)+sweepTol && svC<MathMax(svA,svB)); bool normal=(pvC>pvA+sweepTol && svC<svA); if(sweep){code="A1";name="A1 BSL SWEEP 3D BEARISH";bull=false;is3=true;trigger="C";} else if(normal){code="E1";name="E1 3D NORMAL BEARISH";bull=false;is3=true;trigger="C";}}
   }
   if(code=="" && ArraySize(plB)>=3)
   {
      candCount++;
      int n=ArraySize(plB); pA=plB[n-3];pB=plB[n-2];pC=plB[n-1]; pvA=plV[n-3];pvB=plV[n-2];pvC=plV[n-1];
      bool ga=NearestByBar(slB,slV,pA,InpABCMaxBarGap,sA,svA), gb=NearestByBar(slB,slV,pB,InpABCMaxBarGap,sB,svB), gc=NearestByBar(slB,slV,pC,InpABCMaxBarGap,sC,svC);
      if(ga&&gb&&gc){ bool sweep=(MathAbs(pvA-pvB)<=eqTol && pvC<MathMin(pvA,pvB)-sweepTol && svC>MathMin(svA,svB)); bool normal=(pvC<pvA-sweepTol && svC>svA); if(sweep){code="A2";name="A2 SSL SWEEP 3D BULLISH";bull=true;is3=true;trigger="C";} else if(normal){code="E2";name="E2 3D NORMAL BULLISH";bull=true;is3=true;trigger="C";}}
   }
   if(code=="" && ArraySize(phB)>=2)
   {
      candCount++;
      int n=ArraySize(phB); pA=phB[n-2];pB=phB[n-1]; pvA=phV[n-2];pvB=phV[n-1]; pC=-1;
      bool ga=NearestByBar(shB,shV,pA,InpABCMaxBarGap,sA,svA), gb=NearestByBar(shB,shV,pB,InpABCMaxBarGap,sB,svB);
      if(ga&&gb && pvB>pvA+sweepTol && svB<svA){ if(MathAbs(pvA-pvB)<=eqTol+sweepTol){code="A3";name="A3 BSL SWEEP 2D BEARISH";} else {code="D1";name="D1 2D NORMAL BEARISH";} bull=false;is3=false;trigger="B"; if(InpEnableB1B2&&InpOrderblockHigh>0&&MathAbs(pvB-InpOrderblockHigh)<=zoneTol){code="B1";name="B1 OB RETURN 2D BEARISH";} if(InpEnableC1C2&&InpSupplyZone>0&&MathAbs(pvB-InpSupplyZone)<=zoneTol){code="C1";name="C1 SUPPLY RETURN 2D BEARISH";} }
   }
   if(code=="" && ArraySize(plB)>=2)
   {
      candCount++;
      int n=ArraySize(plB); pA=plB[n-2];pB=plB[n-1]; pvA=plV[n-2];pvB=plV[n-1]; pC=-1;
      bool ga=NearestByBar(slB,slV,pA,InpABCMaxBarGap,sA,svA), gb=NearestByBar(slB,slV,pB,InpABCMaxBarGap,sB,svB);
      if(ga&&gb && pvB<pvA-sweepTol && svB>svA){ if(MathAbs(pvA-pvB)<=eqTol+sweepTol){code="A4";name="A4 SSL SWEEP 2D BULLISH";} else {code="D2";name="D2 2D NORMAL BULLISH";} bull=true;is3=false;trigger="B"; if(InpEnableB1B2&&InpOrderblockLow>0&&MathAbs(pvB-InpOrderblockLow)<=zoneTol){code="B2";name="B2 OB RETURN 2D BULLISH";} if(InpEnableC1C2&&InpDemandZone>0&&MathAbs(pvB-InpDemandZone)<=zoneTol){code="C2";name="C2 DEMAND RETURN 2D BULLISH";} }
   }

   if(code==""){ ClearDivObjects(); return(false); }
   confCount=1;
   int comp=(trigger=="C"?pC:pB);
   int sw=GetSubwindow();
   ClearDivObjects();
   DrawTrend(PREFIX+"P1",0,time[pA],pvA,time[(trigger=="C"?pC:pB)],(trigger=="C"?pvC:pvB),bull?clrLime:clrRed);
   DrawTrend(PREFIX+"S1",sw,time[sA],svA,time[(trigger=="C"?sC:sB)],(trigger=="C"?svC:svB),bull?clrLime:clrRed);
   DrawTxt(PREFIX+"LA",0,time[pA],pvA,"A",clrWhite); DrawTxt(PREFIX+"LB",0,time[pB],pvB,"B",clrWhite);
   DrawTxt(PREFIX+"SA",sw,time[sA],svA,"A",clrWhite); DrawTxt(PREFIX+"SB",sw,time[sB],svB,"B",clrWhite);
   if(is3){ DrawTrend(PREFIX+"P2",0,time[pB],pvB,time[pC],pvC,bull?clrLime:clrRed); DrawTrend(PREFIX+"S2",sw,time[sB],svB,time[sC],svC,bull?clrLime:clrRed); DrawTxt(PREFIX+"LC",0,time[pC],pvC,"C",clrWhite); DrawTxt(PREFIX+"SC",sw,time[sC],svC,"C",clrWhite);}   
   DrawTxt(PREFIX+"NAME",0,time[comp],(bull?low[comp]:high[comp]),name,bull?clrLime:clrRed);
   if(comp==1) AlertDivergence(code,bull,trigger,time[1]);
   if(InpDebugLogs) Print("[DEBUG][MT4] CONFIRMED ",code," ",(bull?"BULL":"BEAR")," tf=",TfStr()," A=",pA," B=",pB,(is3?" C="+IntegerToString(pC):"")," trigger=",trigger," alertEligible=",(comp==1?"1":"0"));
   return(true);
}

int OnInit()
{
   Dbg("OnInit entry");
   IndicatorShortName(IND_SHORTNAME);
   SetIndexBuffer(0,StochMainBuffer); SetIndexStyle(0,DRAW_LINE,STYLE_SOLID,1,clrDeepSkyBlue); SetIndexLabel(0,"Stoch Main");
   SetIndexBuffer(1,StochSignalBuffer); SetIndexStyle(1,DRAW_LINE,STYLE_SOLID,1,clrOrange); SetIndexLabel(1,"Stoch Signal");
   SetIndexBuffer(2,StochSwingHighBuffer); SetIndexStyle(2,DRAW_ARROW,STYLE_SOLID,1,clrLimeGreen); SetIndexArrow(2,159); SetIndexLabel(2,"Stoch Swing High");
   SetIndexBuffer(3,StochSwingLowBuffer); SetIndexStyle(3,DRAW_ARROW,STYLE_SOLID,1,clrTomato); SetIndexArrow(3,159); SetIndexLabel(3,"Stoch Swing Low");
   SetIndexBuffer(4,PriceSwingHighState); SetIndexStyle(4,DRAW_NONE);
   SetIndexBuffer(5,PriceSwingLowState); SetIndexStyle(5,DRAW_NONE);
   SetIndexEmptyValue(2,EMPTY_VALUE); SetIndexEmptyValue(3,EMPTY_VALUE);
   Dbg("OnInit configured");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){ ClearDivObjects(); }

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(InpDebugLogs && gLastStatsBar!=time[0]) Dbg("OnCalculate entry rates_total="+IntegerToString(rates_total)+" prev="+IntegerToString(prev_calculated));
   int minBars=MathMax(MathMax(InpSlowEMA,InpATRPeriod),InpKPeriod+InpDPeriod+InpSlowing)+20;
   if(rates_total<minBars) return(prev_calculated);

   for(int i=0;i<rates_total;i++)
   {
      StochMainBuffer[i]=iStochastic(NULL,0,InpKPeriod,InpDPeriod,InpSlowing,MODE_SMA,0,MODE_MAIN,i);
      StochSignalBuffer[i]=iStochastic(NULL,0,InpKPeriod,InpDPeriod,InpSlowing,MODE_SMA,0,MODE_SIGNAL,i);
   }

   ResetWorkingBuffers(rates_total);
   EvaluatePriceStructure(rates_total,high,low,close);
   EvaluateStochStructure(rates_total);

   int pH=0,pL=0,sH=0,sL=0;
   for(int j=1;j<rates_total-1;j++){if(PriceSwingHighState[j]!=EMPTY_VALUE)pH++; if(PriceSwingLowState[j]!=EMPTY_VALUE)pL++; if(StochSwingHighBuffer[j]!=EMPTY_VALUE)sH++; if(StochSwingLowBuffer[j]!=EMPTY_VALUE)sL++;}
   int candidates=0,confirmed=0;
   DetectAndRender(rates_total,time,high,low,candidates,confirmed);

   if(InpDebugLogs && gLastStatsBar!=time[0])
   {
      Print("[DEBUG][MT4] bars=",rates_total," stochCopied=ok priceSwingsH/L=",pH,"/",pL," stochSwingsH/L=",sH,"/",sL," candidates=",candidates," confirmed=",confirmed);
      gLastStatsBar=time[0];
   }

   return(rates_total);
}
