#property strict
#property indicator_separate_window
#property indicator_minimum 0
#property indicator_maximum 100
#property indicator_plots 4
#property indicator_buffers 6

#property indicator_type1 DRAW_LINE
#property indicator_color1 DeepSkyBlue
#property indicator_label1 "Stoch Main"
#property indicator_type2 DRAW_LINE
#property indicator_color2 Orange
#property indicator_label2 "Stoch Signal"
#property indicator_type3 DRAW_ARROW
#property indicator_color3 LimeGreen
#property indicator_label3 "Stoch Swing High"
#property indicator_type4 DRAW_ARROW
#property indicator_color4 Tomato
#property indicator_label4 "Stoch Swing Low"

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

double ATRBuffer[];
double EMAFastBuffer[];
double EMASlowBuffer[];

int atrHandle=INVALID_HANDLE, emaFastHandle=INVALID_HANDLE, emaSlowHandle=INVALID_HANDLE, stochHandle=INVALID_HANDLE;
string PREFIX="PSD_DIV_MT5_";
string IND_SHORTNAME="Professional Structural Stoch Divergence - Stage2+3 (MT5)";
string gLastAlertKey="";
datetime gLastAlertWhen=0;
datetime gLastStatsBar=0;

void Dbg(string s){ if(InpDebugLogs) PrintFormat("[DEBUG][MT5] %s | chart=%I64d symbol=%s",s,ChartID(),_Symbol); }
string TfStr(){ return(EnumToString((ENUM_TIMEFRAMES)_Period)); }

int GetSubwindow()
{
   int w=ChartWindowFind(0,IND_SHORTNAME);
   if(w<1) w=1;
   return(w);
}

void ResetWorkingBuffers(int total){ for(int i=0;i<total;i++){StochSwingHighBuffer[i]=EMPTY_VALUE;StochSwingLowBuffer[i]=EMPTY_VALUE;PriceSwingHighState[i]=EMPTY_VALUE;PriceSwingLowState[i]=EMPTY_VALUE;}}

void EvaluatePriceStructure(const int total,const double &high[],const double &low[],const double &close[])
{
   int start=total-2,dir=0,extBar=start; double ext=close[start],legStart=close[start];
   for(int i=start;i>=1;i--)
   {
      double atr=ATRBuffer[i]; if(atr<=0) continue;
      double atrSum=0; int c=0; for(int n=0;n<10 && i+n<total;n++){atrSum+=ATRBuffer[i+n];c++;}
      double atrAvg=(c>0?atrSum/c:atr);
      double emaFast=EMAFastBuffer[i], emaSlow=EMASlowBuffer[i], emaFastPrev=EMAFastBuffer[i+1];
      bool compressed=(atrAvg>0 && atr<atrAvg*InpCompressionFactor);
      bool emaQualified=(MathAbs(emaFast-emaSlow)>=atr*InpEMASepATRMult || MathAbs(emaFast-emaFastPrev)>=atr*InpEMASlopeATRMult);
      if(dir==0){legStart=close[i+1]; ext=close[i+1]; extBar=i+1; if(!compressed&&emaQualified){if(close[i]-legStart>=atr*InpImpulseATRMult){dir=1;ext=high[i];extBar=i;} else if(legStart-close[i]>=atr*InpImpulseATRMult){dir=-1;ext=low[i];extBar=i;}}}
      else if(dir==1){if(high[i]>ext){ext=high[i];extBar=i;} if(ext-low[i]>=atr*InpRetraceATRMult){PriceSwingHighState[extBar]=high[extBar];dir=-1;legStart=ext;ext=low[i];extBar=i;}}
      else {if(low[i]<ext){ext=low[i];extBar=i;} if(high[i]-ext>=atr*InpRetraceATRMult){PriceSwingLowState[extBar]=low[extBar];dir=1;legStart=ext;ext=high[i];extBar=i;}}
   }
}

void EvaluateStochStructure(const int total)
{
   int start=total-2,dir=0,extBar=start; double ext=StochMainBuffer[start],legStart=StochMainBuffer[start];
   for(int i=start;i>=1;i--)
   {
      double sv=StochMainBuffer[i], sp=StochMainBuffer[i+1];
      if(dir==0){legStart=sp;ext=sp;extBar=i+1;if(sv-legStart>=InpStochImpulse){dir=1;ext=sv;extBar=i;} else if(legStart-sv>=InpStochImpulse){dir=-1;ext=sv;extBar=i;}}
      else if(dir==1){if(sv>ext){ext=sv;extBar=i;} if(ext-sv>=InpStochRetrace){StochSwingHighBuffer[extBar]=ext;dir=-1;legStart=ext;ext=sv;extBar=i;}}
      else {if(sv<ext){ext=sv;extBar=i;} if(sv-ext>=InpStochRetrace){StochSwingLowBuffer[extBar]=ext;dir=1;legStart=ext;ext=sv;extBar=i;}}
   }
}

void CollectPoints(const int total,const double &highBuf[],const double &lowBuf[],int &bars[],double &vals[],int &types[])
{
   ArrayResize(bars,0); ArrayResize(vals,0); ArrayResize(types,0);
   for(int i=total-2;i>=1;i--)
   {
      bool h=(highBuf[i]!=EMPTY_VALUE), l=(lowBuf[i]!=EMPTY_VALUE); if(!h&&!l) continue;
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

void ClearDivObjects(){ string n[]={"P1","P2","S1","S2","LA","LB","LC","SA","SB","SC","NAME"}; for(int i=0;i<ArraySize(n);i++) ObjectDelete(0,PREFIX+n[i]); }
void DrawTrend(string n,int w,datetime t1,double p1,datetime t2,double p2,color c){ObjectDelete(0,n);ObjectCreate(0,n,OBJ_TREND,w,t1,p1,t2,p2);ObjectSetInteger(0,n,OBJPROP_COLOR,c);ObjectSetInteger(0,n,OBJPROP_WIDTH,2);ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false);} 
void DrawTxt(string n,int w,datetime t,double p,string txt,color c){ObjectDelete(0,n);ObjectCreate(0,n,OBJ_TEXT,w,t,p);ObjectSetString(0,n,OBJPROP_TEXT,txt);ObjectSetInteger(0,n,OBJPROP_COLOR,c);ObjectSetInteger(0,n,OBJPROP_FONTSIZE,9);} 

void AlertDivergence(string code,bool bull,string trig,datetime barTime)
{
   if(!InpEnableAlerts) return;
   string key=_Symbol+"|"+TfStr()+"|"+code+"|"+TimeToString(barTime,TIME_DATE|TIME_MINUTES);
   if(key==gLastAlertKey || gLastAlertWhen==barTime) return;
   string msg=StringFormat("%s|%s|%s|%s|Trigger=%s|%s",_Symbol,TfStr(),code,(bull?"BULLISH":"BEARISH"),trig,TimeToString(barTime,TIME_DATE|TIME_MINUTES));
   Alert(msg); PrintFormat("[ALERT][MT5] %s",msg); gLastAlertKey=key; gLastAlertWhen=barTime;
}

bool DetectAndRender(const int total,const datetime &time[],const double &high[],const double &low[],int &candCount,int &confCount,int pCntH,int pCntL,int sCntH,int sCntL)
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

   double atr=ATRBuffer[1]; if(atr<=0) atr=_Point*100; double eqTol=atr*InpEqualAtrMult, sweepTol=atr*InpSweepAtrMult, zoneTol=atr*InpZoneAtrMult;
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
   if(InpDebugLogs) PrintFormat("[DEBUG][MT5] CONFIRMED %s %s tf=%s A=%d B=%d %s trigger=%s alertEligible=%d | chart=%I64d symbol=%s",code,(bull?"BULL":"BEAR"),TfStr(),pA,pB,(is3?"C="+IntegerToString(pC):""),trigger,(comp==1?1:0),ChartID(),_Symbol);
   return(true);
}


bool EnsureHandles()
{
   if(atrHandle==INVALID_HANDLE) atrHandle=iATR(_Symbol,_Period,InpATRPeriod);
   if(emaFastHandle==INVALID_HANDLE) emaFastHandle=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   if(emaSlowHandle==INVALID_HANDLE) emaSlowHandle=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   if(stochHandle==INVALID_HANDLE) stochHandle=iStochastic(_Symbol,_Period,InpKPeriod,InpDPeriod,InpSlowing,MODE_SMA,STO_LOWHIGH);
   return(atrHandle!=INVALID_HANDLE && emaFastHandle!=INVALID_HANDLE && emaSlowHandle!=INVALID_HANDLE && stochHandle!=INVALID_HANDLE);
}

int OnInit()
{
   Dbg("OnInit entry");
   IndicatorSetString(INDICATOR_SHORTNAME,IND_SHORTNAME);
   SetIndexBuffer(0,StochMainBuffer,INDICATOR_DATA); SetIndexBuffer(1,StochSignalBuffer,INDICATOR_DATA); SetIndexBuffer(2,StochSwingHighBuffer,INDICATOR_DATA); SetIndexBuffer(3,StochSwingLowBuffer,INDICATOR_DATA); SetIndexBuffer(4,PriceSwingHighState,INDICATOR_CALCULATIONS); SetIndexBuffer(5,PriceSwingLowState,INDICATOR_CALCULATIONS);
   PlotIndexSetInteger(2,PLOT_ARROW,159); PlotIndexSetInteger(3,PLOT_ARROW,159); PlotIndexSetDouble(2,PLOT_EMPTY_VALUE,EMPTY_VALUE); PlotIndexSetDouble(3,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   ArraySetAsSeries(StochMainBuffer,true); ArraySetAsSeries(StochSignalBuffer,true); ArraySetAsSeries(StochSwingHighBuffer,true); ArraySetAsSeries(StochSwingLowBuffer,true); ArraySetAsSeries(PriceSwingHighState,true); ArraySetAsSeries(PriceSwingLowState,true); ArraySetAsSeries(ATRBuffer,true); ArraySetAsSeries(EMAFastBuffer,true); ArraySetAsSeries(EMASlowBuffer,true);
   EnsureHandles();
   Dbg(StringFormat("handles atr=%d emaFast=%d emaSlow=%d stoch=%d",atrHandle,emaFastHandle,emaSlowHandle,stochHandle));
   // Never hard-fail attach; retry handle init in OnCalculate if market data was not ready yet.
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){ if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle); if(emaFastHandle!=INVALID_HANDLE) IndicatorRelease(emaFastHandle); if(emaSlowHandle!=INVALID_HANDLE) IndicatorRelease(emaSlowHandle); if(stochHandle!=INVALID_HANDLE) IndicatorRelease(stochHandle); ClearDivObjects(); }

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<=0) return(prev_calculated);
   if(InpDebugLogs && (gLastStatsBar!=time[0])) Dbg(StringFormat("OnCalculate entry rates_total=%d prev=%d",rates_total,prev_calculated));

   int minBars=MathMax(MathMax(InpSlowEMA,InpATRPeriod),InpKPeriod+InpDPeriod+InpSlowing)+20;
   if(rates_total<minBars) return(prev_calculated);

   if(!EnsureHandles()){ Dbg("handles not ready yet; waiting for data"); return(prev_calculated); }

   ArrayResize(ATRBuffer,rates_total); ArrayResize(EMAFastBuffer,rates_total); ArrayResize(EMASlowBuffer,rates_total);
   int cAtr=CopyBuffer(atrHandle,0,0,rates_total,ATRBuffer), cFast=CopyBuffer(emaFastHandle,0,0,rates_total,EMAFastBuffer), cSlow=CopyBuffer(emaSlowHandle,0,0,rates_total,EMASlowBuffer), cMain=CopyBuffer(stochHandle,0,0,rates_total,StochMainBuffer), cSig=CopyBuffer(stochHandle,1,0,rates_total,StochSignalBuffer);
   if(InpDebugLogs && gLastStatsBar!=time[0]) Dbg(StringFormat("copy atr=%d fast=%d slow=%d stMain=%d stSig=%d",cAtr,cFast,cSlow,cMain,cSig));
   if(cAtr<rates_total || cFast<rates_total || cSlow<rates_total || cMain<rates_total || cSig<rates_total) return(prev_calculated);

   ResetWorkingBuffers(rates_total);
   EvaluatePriceStructure(rates_total,high,low,close);
   EvaluateStochStructure(rates_total);

   int pH=0,pL=0,sH=0,sL=0;
   for(int i=1;i<rates_total-1;i++){ if(PriceSwingHighState[i]!=EMPTY_VALUE)pH++; if(PriceSwingLowState[i]!=EMPTY_VALUE)pL++; if(StochSwingHighBuffer[i]!=EMPTY_VALUE)sH++; if(StochSwingLowBuffer[i]!=EMPTY_VALUE)sL++; }
   int candidates=0,confirmed=0;
   DetectAndRender(rates_total,time,high,low,candidates,confirmed,pH,pL,sH,sL);

   if(InpDebugLogs && gLastStatsBar!=time[0])
   {
      PrintFormat("[DEBUG][MT5] bars=%d stochCopied=%d/%d priceSwingsH/L=%d/%d stochSwingsH/L=%d/%d candidates=%d confirmed=%d | chart=%I64d symbol=%s",
         rates_total,cMain,cSig,pH,pL,sH,sL,candidates,confirmed,ChartID(),_Symbol);
      gLastStatsBar=time[0];
   }

   return(rates_total);
}
