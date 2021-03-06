col.SBtarget    <- "#00533E"
col.SBlim       <- "#edb918"
col.SBlimit     <- "#edb918"
col.SBban       <- "#C73C2E"
col.Ftarget     <- "#714C99"
col.betaFtarget <- "#505596"

pt1             <- 0.3528


convert_df <- function(df,name){
  df %>%
    as_tibble %>%
    mutate(age = as.numeric(rownames(df))) %>%
    gather(key=year, value=value, -age, convert=TRUE) %>%
    group_by(year) %>%
    #        summarise(value=sum(value)) %>%
    mutate(type="VPA",sim="s0",stat=name)
}

#'
#' @export
convert_2d_future <- function(df, name, label="tmp"){
  df %>%
    as_tibble %>%
    mutate(year=rownames(df)) %>%
    gather(key=sim, value=value, -year, convert=TRUE) %>%
    mutate(year=as.numeric(year), stat=name, label=label)
}

#' future.vpaの結果オブジェクトをtibble形式に変換する関数
#'
#' @param fout future.vpaの結果のオブジェクト
#'
#' @encoding UTF-8
#' @export
#'

convert_future_table <- function(fout,label="tmp"){

    U_table <- fout$vwcaa/fout$vbiom
    if(is.null(fout$Fsakugen)) fout$Fsakugen <- -(1-fout$faa[1,,]/fout$currentF[1])
    if(is.null(fout$recruit))  fout$recruit <- fout$naa[1,,]

    ssb      <- convert_2d_future(df=fout$vssb,   name="SSB",     label=label)
    catch    <- convert_2d_future(df=fout$vwcaa,  name="catch",   label=label)
    biomass  <- convert_2d_future(df=fout$vbiom,  name="biomass", label=label)
    U_table  <- convert_2d_future(df=U_table,     name="U",       label=label)
    beta_gamma    <- convert_2d_future(df=fout$alpha,  name="beta_gamma",   label=label)
    Fsakugen <- convert_2d_future(df=fout$Fsakugen, name="Fsakugen",   label=label)
    recruit  <- convert_2d_future(df=fout$recruit, name="Recruitment",   label=label)
    if(!is.null(fout$Fratio)){
        Fratio <- convert_2d_future(df=fout$Fratio, name="Fratio",   label=label)
    }
    else{
        Fratio <- NULL
    }

    Fsakugen_ratio <- Fsakugen %>%
        mutate(value=value+1)
    Fsakugen_ratio$stat <- "Fsakugen_ratio"

    bind_rows(ssb,catch,biomass,beta_gamma,Fsakugen,Fsakugen_ratio,recruit, U_table, Fratio)
}


convert_vector <- function(vector,name){
  vector %>%
    as_tibble %>%
    mutate(year = as.integer(names(vector))) %>%
    mutate(type="VPA",sim="s0",stat=name,age=NA)
}

#' VPAの結果オブジェクトをtibble形式に変換する関数
#'
#' @param vpares vpaの結果のオブジェクト
#' @encoding UTF-8
#'
#'
#' @export

convert_vpa_tibble <- function(vpares,SPRtarget=NULL){

  if (is.null(vpares$input$dat$waa.catch)) {
    total.catch <- colSums(vpares$input$dat$caa*vpares$input$dat$waa,na.rm=T)
  } else {
    total.catch <- colSums(vpares$input$dat$caa*vpares$input$dat$waa.catch,na.rm=T)
  }
  U <- total.catch/colSums(vpares$baa, na.rm=T)

  SSB <- convert_vector(colSums(vpares$ssb,na.rm=T),"SSB") %>%
    dplyr::filter(value>0&!is.na(value))
  Biomass <- convert_vector(colSums(vpares$baa,na.rm=T),"biomass") %>%
    dplyr::filter(value>0&!is.na(value))
  FAA <- convert_df(vpares$faa,"fishing_mortality") %>%
    dplyr::filter(value>0&!is.na(value))
  Recruitment <- convert_vector(colSums(vpares$naa[1,,drop=F]),"Recruitment") %>%
    dplyr::filter(value>0&!is.na(value))

  if(!is.null(SPRtarget)){
    if(is.null(vpares$input$dat$waa.catch)) waa.catch <- vpares$input$dat$waa
    else waa.catch <- vpares$input$dat$waa.catch
    Fratio <- purrr::map_dfc(1:ncol(vpares$naa),
                             function(i){
                               tmp <- !is.na(vpares$faa[,i])
                               calc_Fratio(faa=vpares$faa[tmp,i],
                                           maa=vpares$input$dat$maa[tmp,i],
                                           waa=vpares$input$dat$waa[tmp,i],
                                           M  =vpares$input$dat$M[tmp,i],
                                           waa.catch=waa.catch[tmp],
                                           SPRtarget=SPRtarget)
                             })
    colnames(Fratio) <- colnames(vpares$naa)
    Fratio <- convert_df(Fratio,"Fratio")
  }
  else{
    Fratio <- NULL
  }

  all_table <- bind_rows(SSB,
                         Biomass,
                         convert_vector(U[U>0],"U"),
                         convert_vector(total.catch[total.catch>0],"catch"),
                         convert_df(vpares$naa,"fish_number"),
                         FAA,
                         convert_df(vpares$input$dat$waa,"weight"),
                         convert_df(vpares$input$dat$maa,"maturity"),
                         convert_df(vpares$input$dat$caa,"catch_number"),
                         Recruitment,
                         Fratio)
}

#' fit.SRの結果をtibble形式に治す
#'
#' @param SR_result fit.SRの結果のオブジェクト
#' @encoding UTF-8
#'
#' @export
#'

convert_SR_tibble <- function(res_SR){
    bind_rows(tibble(value=as.numeric(res_SR$pars),type="parameter",name=names(res_SR$pars)),
              res_SR$pred %>% mutate(type="prediction",name="prediction"),
              res_SR$input$SRdata %>% as_tibble() %>%
              mutate(type="observed",name="observed",residual=res_SR$resid))
}

#' 再生産関係をプロットする関数
#'
#' @param SR_result fit.SRの結果のオブジェクト
#' @encoding UTF-8
#'
#' @export
#'

SRplot_gg <- plot.SR <- function(SR_result,refs=NULL,xscale=1000,xlabel="千トン",yscale=1,ylabel="尾",
                                 labeling.year=NULL,add.info=TRUE, recruit_intercept=0,
                                 plot_CI=FALSE, CI=0.9){

  if(is.null(refs$Blimit) && !is.null(refs$Blim)) refs$Blimit <- refs$Blim

  if (SR_result$input$SR=="HS") SRF <- function(SSB,a,b,recruit_intercept=0) (ifelse(SSB*xscale>b,b*a,SSB*xscale*a)+recruit_intercept)/yscale
  if (SR_result$input$SR=="BH") SRF <- function(SSB,a,b,recruit_intercept=0) (a*SSB*xscale/(1+b*SSB*xscale)+recruit_intercept)/yscale
  if (SR_result$input$SR=="RI") SRF <- function(SSB,a,b,recruit_intercept=0) (a*SSB*xscale*exp(-b*SSB*xscale)+recruit_intercept)/yscale

  SRF_CI <- function(CI,sigma,sign,...){
      exp(log(SRF(...))+qnorm(1-(1-CI)/2)*sigma*sign)
  }

  SRdata <- as_tibble(SR_result$input$SRdata) %>%
    mutate(type="obs")
  SRdata.pred <- as_tibble(SR_result$pred) %>%
      mutate(type="pred", year=NA, R=R)
  alldata <- bind_rows(SRdata,SRdata.pred) %>%
    mutate(R=R/yscale,SSB=SSB/xscale)
  ymax <- max(alldata$R)
  year.max <- max(alldata$year,na.rm=T)
  tmp <- 1950:2030
  if(is.null(labeling.year)) labeling.year <- c(tmp[tmp%%5==0],year.max)
  alldata <- alldata %>% mutate(pick.year=ifelse(year%in%labeling.year,year,""))

  g1 <- ggplot(data=alldata,mapping=aes(x=SSB,y=R)) +
    stat_function(fun=SRF,args=list(a=SR_result$pars$a,
                                    b=SR_result$pars$b),color="deepskyblue3",lwd=1.3,
                  n=5000)
    
  if(isTRUE(plot_CI)){
      g1 <- g1+
          stat_function(fun=SRF_CI,
                        args=list(a=SR_result$pars$a,
                                  b=SR_result$pars$b,
                                  sigma=SR_result$pars$sd,
                                  sign=-1,
                                  CI=CI),
                        color="deepskyblue3",lty=3,n=5000)+
          stat_function(fun=SRF_CI,
                        args=list(a=SR_result$pars$a,
                                  b=SR_result$pars$b,
                                  sigma=SR_result$pars$sd,
                                  sign=1,
                                  CI=CI),
                        color="deepskyblue3",lty=3,n=5000)
  }
    
  g1 <- g1+  geom_path(data=dplyr::filter(alldata,type=="obs"),
              aes(y=R,x=SSB),color="black") +
    geom_point(data=dplyr::filter(alldata,type=="obs"),
               aes(y=R,x=SSB),shape=21,fill="white") +
    ggrepel::geom_text_repel(data=dplyr::filter(alldata,type=="obs"),
                             segment.alpha=0.5,nudge_y=5,
                             aes(y=R,x=SSB,label=pick.year)) +
    theme_bw(base_size=14)+
    theme(legend.position = 'none') +
    theme(panel.grid = element_blank()) +
    xlab(str_c("親魚資源量 (",xlabel,")"))+
    ylab(str_c("加入尾数 (",ylabel,")"))+
    coord_cartesian(ylim=c(0,ymax*1.05),expand=0)

  if(recruit_intercept>0){
    g1 <- g1+stat_function(fun=SRF,
                           args=list(a=SR_result$pars$a,
                                     b=SR_result$pars$b,
                                     recruit_intercept=recruit_intercept),
                           color="deepskyblue3",lwd=1.3,lty=2)
  }

  if(add.info){
    g1 <- g1+labs(caption=str_c("関数形: ",SR_result$input$SR,", 自己相関: ",SR_result$input$AR,
                                ", 最適化法",SR_result$input$method,", AICc: ",round(SR_result$AICc,2)))
  }

  if(!is.null(refs)){
    g1 <- g1+geom_vline(xintercept=c(refs$Bmsy/xscale,refs$Blimit/xscale,refs$Bban/xscale),
                        linetype=2,
                        col=c(col.SBtarget,col.SBlimit,col.SBban))
  }
  g1
}

get.trace <- function(trace){
  trace <- trace  %>% as_tibble() %>%
    select(starts_with("TC-mean"),ssb.mean,fmulti,catch.CV) %>%
    mutate(label=as.character(1:nrow(.)))

  trace <- trace %>% gather(value=value,key=age,-label,-fmulti,-ssb.mean,-catch.CV) %>%
    mutate(age=str_extract(age, "(\\d)+")) %>%
    mutate(age=factor(age)) %>%
    mutate(age=fct_reorder(age,length(age):1))
  return(trace)
}

#' 漁獲量曲線(yield curve)を書く
#'
#' @param MSY_obj est.MSYの結果のオブジェクト
#' @param refs_base est.MSYから得られる管理基準値の表
#' @param future 将来予測結果のリスト。与えられると将来予測の結果を重ね書きする
#' @param future.replicat 将来予測結果から特定のreplicateのみを示す。futureで与えたリストの長さのベクトルを与える。
#' @param past  VPA結果。与えられると過去の推定値を重ね書きする
#' @encoding UTF-8
#'
#' @export

plot_yield <- function(MSY_obj,refs_base,
                       refs.label=NULL, # label for reference point
                       refs.color=c("#00533E","#edb918","#C73C2E"),
                       AR_select=FALSE,xlim.scale=1.1,
                       biomass.unit=1,labeling=TRUE,lining=TRUE,
                       age.label.ratio=0.9, # 年齢のラベルを入れる位置（xの最大値からの割合)
                       #                       family = "JP1",
                       ylim.scale=1.2,future=NULL,
                       future.replicate=NULL,
                       past=NULL,
                       past_year_range=NULL,
                       future.name=NULL){

  junit <- c("","十","百","千","万")[log10(biomass.unit)+1]

  if ("trace" %in% names(MSY_obj)) {
    trace.msy <- MSY_obj$trace
  } else {
    trace.msy <- MSY_obj
  }

  #    require(tidyverse,quietly=TRUE)
  #    require(ggrepel)

  trace <- get.trace(trace.msy) %>%
    mutate("年齢"=age,ssb.mean=ssb.mean/biomass.unit,value=value/biomass.unit) %>%
    dplyr::filter(!is.na(value))

  refs_base <- refs_base %>%
    mutate(RP.definition=ifelse(is.na(RP.definition),"",RP.definition)) %>%
    mutate(SSB=SSB/biomass.unit)
  if("AR"%in%names(refs_base)) refs_base <- refs_base %>% dplyr::filter(AR==AR_select)

  ymax <- trace %>%
    group_by(ssb.mean) %>%
    summarise(catch.mean=sum(value))
  ymax <- max(ymax$catch.mean)


  g1 <- trace %>%
    ggplot2::ggplot()

  if(is.null(future.name)) future.name <- 1:length(future)

  if(is.null(refs.label)) {
    refs.label <- str_c(refs_base$RP_name,":",refs_base$RP.definition)
    refs.color <- 1:length(refs.label)
  }
  refs_base$refs.label <- refs.label

  xmax <- max(trace$ssb.mean,na.rm=T)
  age.label.position <- trace$ssb.mean[which.min((trace$ssb.mean-xmax*xlim.scale*age.label.ratio)^2)]
  age.label <- trace %>% dplyr::filter(round(age.label.position,1)==round(ssb.mean,1))%>%
    mutate(cumcatch=cumsum(value)-value/2)%>%
    mutate(age=as.numeric(as.character(age)))
  age.label <- age.label %>%
    mutate(age_name=str_c("Age ",age,ifelse(age.label$age==max(age.label$age),"+","")))

  g1 <- g1 + geom_area(aes(x=ssb.mean,y=value,fill=年齢),col="black",alpha=0.5,lwd=1*0.3528) +
    #    geom_line(aes(x=ssb.mean,y=catch.CV,fill=age)) +
    #    scale_y_continuous(sec.axis = sec_axis(~.*5, name = "CV catch"))+
    scale_fill_brewer() +
    theme_bw() +
    theme(legend.position = 'none') +
    #    geom_point(data=refs_base,aes(y=Catch,x=SSB,shape=refs.label,color=refs.label),size=4)+
    #形は塗りつぶしができる形にすること
    scale_shape_manual(values = c(21, 24,5,10)) +
    #塗りつぶし色を指定する
    scale_color_manual(values = c("darkgreen", "darkblue","orange","yellow"))+
    theme(panel.grid = element_blank(),axis.text=element_text(color="black")) +
    coord_cartesian(xlim=c(0,xmax*xlim.scale),
                    ylim=c(0,ymax*ylim.scale),expand=0) +
    geom_text(data=age.label,
              mapping = aes(y = cumcatch, x = ssb.mean, label = age_name)#,
              #                            family = family
    ) +
    #    geom_text_repel(data=refs_base,
    #                     aes(y=Catch,x=SSB,label=refs.label),
    #                     size=4,box.padding=0.5,segment.color="gray",
    #                     hjust=0,nudge_y      = ymax*ylim.scale-refs_base$Catch,
    #    direction    = "y",
    #    angle        = 0,
    #    vjust        = 0,
    #        segment.size = 1)+
    xlab(str_c("平均親魚量 (",junit,"トン)")) + ylab(str_c("平均漁獲量 (",junit,"トン)"))

  if(!is.null(future)){
    futuredata <- NULL
    for(j in 1:length(future)){
      if(class(future[[j]])=="future_new"){
        future_init <- future[[j]]$input$tmb_data$future_initial_year
        future_init <- as.numeric(dimnames(future[[j]]$naa)[[2]][future_init])
        future[[j]] <- format_to_old_future(future[[j]])
      }
      else{
        future_init <- 0
      }
      if(is.null(future.replicate)){
        futuredata <- bind_rows(futuredata,
                                tibble(
                                  year        =as.numeric(rownames(future[[j]]$vssb)),
                                  ssb.future  =apply(future[[j]]$vssb[,-1],1,mean)/biomass.unit,
                                  catch.future=apply(future[[j]]$vwcaa[,-1],1,mean)/biomass.unit,
                                  scenario=future.name[j]))
      }
      else{
        futuredata <- bind_rows(futuredata,
                                tibble(
                                  year        =as.numeric(rownames(future[[j]]$vssb)),
                                  ssb.future  =future[[j]]$vssb[,future.replicate[j]]/biomass.unit,
                                  catch.future=future[[j]]$vwcaa[,future.replicate[j]]/biomass.unit,
                                  scenario=future.name[j]))
      }
      futuredata <- futuredata %>% group_by(scenario) %>%
        dplyr::filter(year > future_init)
      g1 <- g1 +
        geom_path(data=futuredata,
                  mapping=aes(x       =ssb.future,
                              y       = catch.future,
                              linetype=factor(scenario),
                              color   = factor(scenario)),
                  lwd=1)+
        geom_point(data=futuredata,
                   mapping=aes(x    =ssb.future,
                               y    =catch.future,
                               shape=factor(scenario),
                               color=factor(scenario)),
                   size=3)
    }
  }

  if(!is.null(past)){
    catch.past = unlist(colSums(past$input$dat$caa*past$input$dat$waa, na.rm=T)/biomass.unit)
    if (past$input$last.catch.zero && !is.null(future)) {
      catch.past[length(catch.past)] = apply(future[[1]]$vwcaa[,-1],1,mean)[1]/biomass.unit
    }
    pastdata <- tibble(
      year      =as.numeric(colnames(past$ssb)),
      ssb.past  =unlist(colSums(past$ssb, na.rm=T))/biomass.unit,
      catch.past=catch.past
    )

    if(past_year_range[1] > 0 && !is.null(past_year_range))
        pastdata <- pastdata %>% dplyr::filter(year%in%past_year_range)

    g1 <- g1 +
      geom_path(data=pastdata,
                mapping=aes(x=ssb.past,y=catch.past),
                color="darkred",lwd=1,alpha=0.9)
  }

  if(isTRUE(lining)){
    #        ylim.scale.factor <- rep(c(0.94,0.97),ceiling(length(refs.label)/2))[1:length(refs.label)]
    g1 <- g1 + geom_vline(xintercept=refs_base$SSB,lty="41",lwd=0.6,color=refs.color)+
      ggrepel::geom_label_repel(data=refs_base,
                                aes(y=ymax*ylim.scale*0.85,
                                    x=SSB,label=refs.label),
                                direction="x",size=11*0.282,nudge_y=ymax*ylim.scale*0.9)
  }

  if(isTRUE(labeling)){
    g1 <- g1 +
      geom_point(data=refs_base,
                 aes(y=Catch,x=SSB))+
      ggrepel::geom_label_repel(data=refs_base,
                                aes(y=Catch,x=SSB,label=refs.label),
                                #                            size=4,box.padding=0.5,segment.color="black",
                                hjust=0,#nudge_y      = ymax*ylim.scale-refs_base$Catch/2,
                                direction="y",angle=0,vjust        = 0,segment.size = 1)
    #             geom_label_repel(data=tibble(x=c(1,limit.ratio,ban.ratio),
    #                                          y=max.U,
    #                                          label=c("目標管理基準値","限界管理基準値","禁漁水準")),
    #                              aes(x=x,y=y,label=label),
    #                              direction="y",angle=0,nudge_y=max.U
  }


  return(g1)

}

#' 管理基準値の表を作成する
#'
#' @param refs_base est.MSYから得られる管理基準値の表
#' @encoding UTF-8
#'
#' @export
#'

make_RP_table <- function(refs_base){
  #    require(formattable)
  #    require(tidyverse,quietly=TRUE)
  table_output <- refs_base %>%
    select(-RP_name) %>% # どの列を表示させるか選択する
    # 各列の有効数字を指定
    mutate(SSB=round(SSB,-floor(log10(min(SSB)))),
           SSB2SSB0=round(SSB2SSB0,2),
           Catch=round(Catch,-floor(log10(min(Catch)))),
           Catch.CV=round(Catch.CV,2),
           U=round(U,2),
           Fref2Fcurrent=round(Fref2Fcurrent,2)) %>%
    rename("管理基準値"=RP.definition,"親魚資源量"=SSB,"B0に対する比"=SSB2SSB0,
           "漁獲量"=Catch,"漁獲量の変動係数"=Catch.CV,"漁獲率"=U,"努力量の乗数"=Fref2Fcurrent)

  table_output  %>%
    # 表をhtmlで出力
    formattable::formattable(list(親魚資源量=color_bar("olivedrab"),
                                       漁獲量=color_bar("steelblue"),
                                       漁獲率=color_bar("orange"),
                                       努力量の乗数=color_bar("tomato")))

  #    return(table_output)

}

#' 管理基準値表から目的の管理基準値を取り出す関数
#'
#' @param refs_base est.MSYから得られる管理基準値の表
#' @param RP_name 取り出したい管理基準値の名前
#' @encoding UTF-8
#'
#' @export
#'

derive_RP_value <- function(refs_base,RP_name){
  #    refs_base %>% dplyr::filter(RP.definition%in%RP_name)
  #    subset(refs_base,RP.definition%in%RP_name)
  refs_base[refs_base$RP.definition%in%RP_name,]
}

#' Kobe II matrixを計算するための関数
#'
#' @param fres_base future.vpaの結果のオブジェクト
#' @param refs_base est.MSYから得られる管理基準値の表
#' @encoding UTF-8
#'
#' @export

calc_kobeII_matrix <- function(fres_base,
                               refs_base,
                               Btarget=c("Btarget0"),
                               Blimit=c("Blimit0"),
                               #                              Blow=c("Blow0"),
                               Bban=c("Bban0"),
                               year.lag=0,
                               beta=seq(from=0.5,to=1,by=0.1)){
  #    require(tidyverse,quietly=TRUE)
  # HCRの候補を網羅的に設定
  #    HCR_candidate1 <- expand.grid(
  #        Btarget_name=refs_base$RP.definition[str_detect(refs_base$RP.definition,Btarget)],
  #        Blow_name=refs_base$RP.definition[str_detect(refs_base$RP.definition,Blow)],
  #        Blimit_name=refs_base$RP.definition[str_detect(refs_base$RP.definition,Blimit)],
  #        Bban_name=refs_base$RP.definition[str_detect(refs_base$RP.definition,Bban)],
  #        beta=beta)

  refs.unique <- unique(c(Btarget,Blimit,Bban))
  tmp <- !refs.unique%in%refs_base$RP.definition
  if(sum(tmp)>0) stop(refs.unique[tmp]," does not appear in column of RP.definition\n")

  HCR_candidate1 <- expand.grid(
    Btarget_name=derive_RP_value(refs_base,Btarget)$RP.definition,
    #        Blow_name=derive_RP_value(refs_base,Blow)$RP.definition,
    Blimit_name=derive_RP_value(refs_base,Blimit)$RP.definition,
    Bban_name=derive_RP_value(refs_base,Bban)$RP.definition,
    beta=beta)

  HCR_candidate2 <- expand.grid(
    Btarget=derive_RP_value(refs_base,Btarget)$SSB,
    #        Blow=derive_RP_value(refs_base,Blow)$SSB,
    Blimit=derive_RP_value(refs_base,Blimit)$SSB,
    Bban=derive_RP_value(refs_base,Bban)$SSB,
    beta=beta) %>% select(-beta)

  HCR_candidate <- bind_cols(HCR_candidate1,HCR_candidate2) %>% as_tibble()

  HCR_candidate <- refs_base %>% #dplyr::filter(str_detect(RP.definition,Btarget)) %>%
    dplyr::filter(RP.definition%in%Btarget) %>%
    mutate(Btarget_name=RP.definition,Fmsy=Fref2Fcurrent) %>%
    select(Btarget_name,Fmsy) %>%
    left_join(HCR_candidate) %>%
    arrange(Btarget_name,Blimit_name,Bban_name,desc(beta))

  HCR_candidate$HCR_name <- str_c(HCR_candidate$Btarget_name,
                                  HCR_candidate$Blimit_name,
                                  HCR_candidate$Bban_name,sep="-")
  fres_base$input$outtype <- "FULL"
  kobeII_table <- HCR.simulation(fres_base$input,HCR_candidate,year.lag=year.lag)

  cat(length(unique(HCR_candidate$HCR_name)), "HCR is calculated: ",
      unique(HCR_candidate$HCR_name),"\n")

  kobeII_data <- left_join(kobeII_table,HCR_candidate)
  return(kobeII_data)
}

#'
#' @export
#'

make_kobeII_table0 <- function(kobeII_data,
                               res_vpa,
                               year.catch=(max(as.numeric(colnames(res_vpa$naa)))+1:10),
                               year.ssb=(max(as.numeric(colnames(res_vpa$naa)))+1:10),
                               year.Fsakugen=(max(as.numeric(colnames(res_vpa$naa)))+1:10),
                               year.ssbtarget=(max(as.numeric(colnames(res_vpa$naa)))+1:10),
                               year.ssblimit=(max(as.numeric(colnames(res_vpa$naa)))+1:10),
                               year.ssbban=(max(as.numeric(colnames(res_vpa$naa)))+1:10),
                               year.ssbmin=(max(as.numeric(colnames(res_vpa$naa)))+1:10),
                               year.ssbmax=(max(as.numeric(colnames(res_vpa$naa)))+1:10),
                               year.aav=(max(as.numeric(colnames(res_vpa$naa)))+1:10))
{
  # 平均漁獲量
  (catch.table <- kobeII.data %>%
     dplyr::filter(year%in%year.catch,stat=="catch") %>% # 取り出す年とラベル("catch")を選ぶ
     group_by(HCR_name,beta,year) %>%
     summarise(catch.mean=round(mean(value))) %>%  # 値の計算方法を指定（漁獲量の平均ならmean(value)）
     # "-3"とかの値で桁数を指定
     spread(key=year,value=catch.mean) %>% ungroup() %>%
     arrange(HCR_name,desc(beta)) %>% # HCR_nameとbetaの順に並び替え
     mutate(stat_name="catch.mean"))

  # 平均親魚
  (ssb.table <- kobeII.data %>%
      dplyr::filter(year%in%year.ssb,stat=="SSB") %>%
      group_by(HCR_name,beta,year) %>%
      summarise(ssb.mean=round(mean(value))) %>%
      spread(key=year,value=ssb.mean) %>% ungroup() %>%
      arrange(HCR_name,desc(beta)) %>% # HCR_nameとbetaの順に並び替え
      mutate(stat_name="ssb.mean"))

  # 1-currentFに乗じる値=currentFからの努力量の削減率の平均値（実際には確率分布になっている）
  (Fsakugen.table <- kobeII.data %>%
      dplyr::filter(year%in%year.Fsakugen,stat=="Fsakugen") %>% # 取り出す年とラベル("catch")を選ぶ
      group_by(HCR_name,beta,year) %>%
      summarise(Fsakugen=round(mean(value),2)) %>%
      spread(key=year,value=Fsakugen) %>% ungroup() %>%
      arrange(HCR_name,desc(beta)) %>% # HCR_nameとbetaの順に並び替え
      mutate(stat_name="Fsakugen"))

  # SSB>SSBtargetとなる確率
  ssbtarget.table <- kobeII.data %>%
    dplyr::filter(year%in%year.ssbtarget,stat=="SSB") %>%
    group_by(HCR_name,beta,year) %>%
    summarise(ssb.over=round(100*mean(value>Btarget))) %>%
    spread(key=year,value=ssb.over) %>%
    ungroup() %>%
    arrange(HCR_name,desc(beta))%>%
    mutate(stat_name="Pr(SSB>SSBtarget)")

  # SSB>SSBlimとなる確率
  ssblimit.table <- kobeII.data %>%
    dplyr::filter(year%in%year.ssblimit,stat=="SSB") %>%
    group_by(HCR_name,beta,year) %>%
    summarise(ssb.over=round(100*mean(value>Blimit))) %>%
    spread(key=year,value=ssb.over)%>%
    ungroup() %>%
    arrange(HCR_name,desc(beta))%>%
    mutate(stat_name="Pr(SSB>SSBlim)")

  # SSB>SSBbanとなる確率
  ssbban.table <- kobeII.data %>%
    dplyr::filter(year%in%year.ssbban,stat=="SSB") %>%
    group_by(HCR_name,beta,year) %>%
    summarise(ssb.over=round(100*mean(value>Bban))) %>%
    spread(key=year,value=ssb.over)%>%
    ungroup() %>%
    arrange(HCR_name,desc(beta))%>%
    mutate(stat_name="Pr(SSB>SSBban)")

  # SSB>SSBmin(過去最低親魚量を上回る確率)
  ssb.min <- min(unlist(colSums(res_vpa$ssb, na.rm=T)))
  ssbmin.table <- kobeII.data %>%
    dplyr::filter(year%in%year.ssbmin,stat=="SSB") %>%
    group_by(HCR_name,beta,year) %>%
    summarise(ssb.over=round(100*mean(value>ssb.min))) %>%
    spread(key=year,value=ssb.over)%>%
    ungroup() %>%
    arrange(HCR_name,desc(beta))%>%
    mutate(stat_name="Pr(SSB>SSBmin)")

  # SSB>SSBmax(過去最低親魚量を上回る確率)
  ssb.max <- max(unlist(colSums(res_vpa$ssb, na.rm=T)))
  ssbmax.table <- kobeII.data %>%
    dplyr::filter(year%in%year.ssbmax,stat=="SSB") %>%
    group_by(HCR_name,beta,year) %>%
    summarise(ssb.over=round(100*mean(value>ssb.max))) %>%
    spread(key=year,value=ssb.over)%>%
    ungroup() %>%
    arrange(HCR_name,desc(beta))%>%
    mutate(stat_name="Pr(SSB>SSBmax)")

  # オプション: Catch AAV mean
  calc.aav <- function(x)sum(abs(diff(x)))/sum(x[-1])
  catch.aav.table <- kobeII.data %>%
    dplyr::filter(year%in%year.aav,stat=="catch") %>%
    group_by(HCR_name,beta,sim) %>%
    dplyr::summarise(catch.aav=(calc.aav(value))) %>%
    group_by(HCR_name,beta) %>%
    summarise(catch.aav.mean=mean(catch.aav)) %>%
    arrange(HCR_name,desc(beta))%>%
    mutate(stat_name="catch.csv (recent 5 year)")

  res_list <- list(average.catch   = catch.table,
                   average.ssb     = ssb.table,
                   prob.ssbtarget  = ssbtarget.table,
                   prob.ssblimit   = ssblimit.table,
                   prob.ssbban     = ssbban.table,
                   prob.ssbmin     = ssbmin.table,
                   prob.ssbmax     = ssbmax.table,
                   catch.aav       = catch.aav.table)
  return(res_list)

}

#'
#' @export
#'

make_kobeII_table <- function(kobeII_data,
                              res_vpa,
                              year.catch=(max(as.numeric(colnames(res_vpa$naa)))+1:10),
                              year.ssb=(max(as.numeric(colnames(res_vpa$naa)))+1:10),
                              year.Fsakugen=(max(as.numeric(colnames(res_vpa$naa)))+1:10),
                              year.ssbtarget=(max(as.numeric(colnames(res_vpa$naa)))+1:10),
                              year.ssblimit=(max(as.numeric(colnames(res_vpa$naa)))+1:10),
                              year.ssbban=(max(as.numeric(colnames(res_vpa$naa)))+1:10),
                              year.ssbmin=(max(as.numeric(colnames(res_vpa$naa)))+1:10),
                              year.ssbmax=(max(as.numeric(colnames(res_vpa$naa)))+1:10),
                              year.aav=(max(as.numeric(colnames(res_vpa$naa)))+1:10),
                              year.catchdiff=(max(as.numeric(colnames(res_vpa$naa)))+1:10),
                              Btarget=0,
                              Blimit=0,
                              Bban=0){
  # 平均漁獲量
  (catch.mean <- kobeII_data %>%
     dplyr::filter(year%in%year.catch,stat=="catch") %>% # 取り出す年とラベル("catch")を選ぶ
     group_by(HCR_name,beta,year) %>%
     summarise(catch.mean=mean(value)) %>%  # 値の計算方法を指定（漁獲量の平均ならmean(value)）
     # "-3"とかの値で桁数を指定
     spread(key=year,value=catch.mean) %>% ungroup() %>%
     arrange(HCR_name,desc(beta)) %>% # HCR_nameとbetaの順に並び替え
     mutate(stat_name="catch.mean"))

  # 平均親魚
  (ssb.mean <- kobeII_data %>%
      dplyr::filter(year%in%year.ssb,stat=="SSB") %>%
      group_by(HCR_name,beta,year) %>%
      summarise(ssb.mean=mean(value)) %>%
      spread(key=year,value=ssb.mean) %>% ungroup() %>%
      arrange(HCR_name,desc(beta)) %>% # HCR_nameとbetaの順に並び替え
      mutate(stat_name="ssb.mean"))

  # 親魚, 下10%
  (ssb.ci10 <- kobeII_data %>%
      dplyr::filter(year%in%year.ssb,stat=="SSB") %>%
      group_by(HCR_name,beta,year) %>%
      summarise(ssb.ci10=quantile(value,probs=0.1)) %>%
      spread(key=year,value=ssb.ci10) %>% ungroup() %>%
      arrange(HCR_name,desc(beta)) %>% # HCR_nameとbetaの順に並び替え
      mutate(stat_name="ssb.ci10"))

  # 親魚, 上10%
  (ssb.ci90 <- kobeII_data %>%
      dplyr::filter(year%in%year.ssb,stat=="SSB") %>%
      group_by(HCR_name,beta,year) %>%
      summarise(ssb.ci90=quantile(value,probs=0.9)) %>%
      spread(key=year,value=ssb.ci90) %>% ungroup() %>%
      arrange(HCR_name,desc(beta)) %>% # HCR_nameとbetaの順に並び替え
      mutate(stat_name="ssb.ci90"))

  # 1-currentFに乗じる値=currentFからの努力量の削減率の平均値（実際には確率分布になっている）
  (Fsakugen.table <- kobeII_data %>%
      dplyr::filter(year%in%year.Fsakugen,stat=="Fsakugen") %>% # 取り出す年とラベル("catch")を選ぶ
      group_by(HCR_name,beta,year) %>%
      summarise(Fsakugen=round(mean(value),2)) %>%
      spread(key=year,value=Fsakugen) %>% ungroup() %>%
      arrange(HCR_name,desc(beta)) %>% # HCR_nameとbetaの順に並び替え
      mutate(stat_name="Fsakugen"))

  # SSB>SSBtargetとなる確率
  ssbtarget.table <- kobeII_data %>%
    dplyr::filter(year%in%year.ssbtarget,stat=="SSB") %>%
    group_by(HCR_name,beta,year) %>%
    summarise(ssb.over=round(100*mean(value>Btarget))) %>%
    spread(key=year,value=ssb.over) %>%
    ungroup() %>%
    arrange(HCR_name,desc(beta))%>%
    mutate(stat_name="Pr(SSB>SSBtarget)")

  # SSB>SSBlimとなる確率
  ssblimit.table <- kobeII_data %>%
    dplyr::filter(year%in%year.ssblimit,stat=="SSB") %>%
    group_by(HCR_name,beta,year) %>%
    summarise(ssb.over=round(100*mean(value>Blimit))) %>%
    spread(key=year,value=ssb.over)%>%
    ungroup() %>%
    arrange(HCR_name,desc(beta))%>%
    mutate(stat_name="Pr(SSB>SSBlim)")

  # SSB>SSBbanとなる確率
  ssbban.table <- kobeII_data %>%
    dplyr::filter(year%in%year.ssbban,stat=="SSB") %>%
    group_by(HCR_name,beta,year) %>%
    summarise(ssb.over=round(100*mean(value>Bban))) %>%
    spread(key=year,value=ssb.over)%>%
    ungroup() %>%
    arrange(HCR_name,desc(beta))%>%
    mutate(stat_name="Pr(SSB>SSBban)")

  # SSB>SSBmin(過去最低親魚量を上回る確率)
  ssb.min <- min(unlist(colSums(res_vpa$ssb, na.rm=T)))
  ssbmin.table <- kobeII_data %>%
    dplyr::filter(year%in%year.ssbmin,stat=="SSB") %>%
    group_by(HCR_name,beta,year) %>%
    summarise(ssb.over=round(100*mean(value>ssb.min))) %>%
    spread(key=year,value=ssb.over)%>%
    ungroup() %>%
    arrange(HCR_name,desc(beta))%>%
    mutate(stat_name="Pr(SSB>SSBmin)")

  # SSB>SSBmax(過去最低親魚量を上回る確率)
  ssb.max <- max(unlist(colSums(res_vpa$ssb, na.rm=T)))
  ssbmax.table <- kobeII_data %>%
    dplyr::filter(year%in%year.ssbmax,stat=="SSB") %>%
    group_by(HCR_name,beta,year) %>%
    summarise(ssb.over=round(100*mean(value>ssb.max))) %>%
    spread(key=year,value=ssb.over)%>%
    ungroup() %>%
    arrange(HCR_name,desc(beta))%>%
    mutate(stat_name="Pr(SSB>SSBmax)")

  # オプション: Catch AAV mean
  calc.aav <- function(x)sum(abs(diff(x)))/sum(x[-1])
  catch.aav.table <- kobeII_data %>%
    dplyr::filter(year%in%year.aav,stat=="catch") %>%
    group_by(HCR_name,beta,sim) %>%
    dplyr::summarise(catch.aav=(calc.aav(value))) %>%
    group_by(HCR_name,beta) %>%
    summarise(catch.aav.mean=mean(catch.aav)) %>%
    arrange(HCR_name,desc(beta))%>%
    mutate(stat_name="catch.aav")

  res_list <- list(catch.mean   = catch.mean,
                   ssb.mean         = ssb.mean,
                   ssb.lower10percent            = ssb.ci10,
                   ssb.upper90percent            = ssb.ci90,
                   prob.over.ssbtarget  = ssbtarget.table,
                   prob.over.ssblimit   = ssblimit.table,
                   prob.over.ssbban     = ssbban.table,
                   prob.over.ssbmin     = ssbmin.table,
                   prob.over.ssbmax     = ssbmax.table,
                   catch.aav       = catch.aav.table)
  return(res_list)

}


HCR.simulation <- function(finput,HCRtable,year.lag=year.lag){

  tb <- NULL

  for(i in 1:nrow(HCRtable)){
    HCR_base <- HCRtable[i,]
    finput$multi <- HCR_base$Fmsy
    finput$HCR <- list(Blim=HCR_base$Blimit,Bban=HCR_base$Bban,
                       beta=HCR_base$beta,year.lag=year.lag)
    finput$is.plot <- FALSE
    finput$silent <- TRUE
    fres_base <- do.call(future.vpa,finput) # デフォルトルールの結果→図示などに使う
    tmp <- convert_future_table(fres_base,label=HCRtable$HCR_name[i]) %>%
      rename(HCR_name=label)
    tmp$beta <- HCR_base$beta
    tb <- bind_rows(tb,tmp)
  }
  tb <- tb %>% mutate(HCR_name=str_c("beta",beta)) %>%
    mutate(scenario=HCR_name)
  return(tb)
}

#' kobeII matrixの簡易版（Btarget, Blimitは決め打ちでβのみ変える)
#'
#' @encoding UTF-8
#' @export
#'
#'

beta.simulation <- function(finput,beta_vector,year.lag=0,type="old"){

  tb <- NULL

  for(i in 1:length(beta_vector)){
    if(type=="old"){
      finput$HCR$beta <- beta_vector[i]
      finput$is.plot <- FALSE
      finput$silent <- TRUE
      fres_base <- do.call(future.vpa,finput) # デフォルトルールの結果→図示などに使う
    }
    else{
      finput$tmb_data$HCR_mat[,,"beta"] <- beta_vector[i]
      if(!is.null(finput$MSE_input_data)) finput$MSE_input_data$input$HCR_beta <- beta_vector[i]
      fres_base <- do.call(future_vpa,finput) # デフォルトルールの結果→図示などに使う
      fres_base <- format_to_old_future(fres_base)
    }
    tmp <- convert_future_table(fres_base,label=beta_vector[i]) %>%
      rename(HCR_name=label)  %>% mutate(beta=beta_vector[i])
    tb <- bind_rows(tb,tmp)
  }
  return(tb)
}


get.stat4 <- function(fout,Brefs,
                      refyear=c(2019:2023,2028,2038)){
  col.target <- ifelse(fout$input$N==0,1,-1)
  years <- as.numeric(rownames(fout$vwcaa))

  if(is.null(refyear)){
    refyear <- c(seq(from=min(years),to=min(years)+5),
                 c(min(years)+seq(from=10,to=20,by=5)))
  }

  catch.mean <- rowMeans(fout$vwcaa[years%in%refyear,col.target])
  names(catch.mean) <- str_c("Catch",names(catch.mean))
  catch.mean <- as_tibble(t(catch.mean))

  Btarget.prob <- rowMeans(fout$vssb[years%in%refyear,col.target]>Brefs$Btarget) %>%
    t() %>% as_tibble()
  names(Btarget.prob) <- str_c("Btarget_prob",names(Btarget.prob))

  #    Blow.prob <- rowMeans(fout$vssb[years%in%refyear,col.target]>Brefs$Blow) %>%
  #        t() %>% as_tibble()
  #    names(Blow.prob) <- str_c("Blow_prob",names(Blow.prob))

  Blimit.prob <- rowMeans(fout$vssb[years%in%refyear,col.target]<Brefs$Blimit) %>%
    t() %>% as_tibble()
  names(Blimit.prob) <- str_c("Blimit_prob",names(Blimit.prob))

  Bban.prob <- rowMeans(fout$vssb[years%in%refyear,col.target]<Brefs$Bban) %>%
    t() %>% as_tibble()
  names(Bban.prob) <- str_c("Bban_prob",names(Bban.prob))

  return(bind_cols(catch.mean,Btarget.prob,Blimit.prob,Bban.prob))
}

#' Kobe plotを書く
#'
#' @param vpares VPAの結果のオブジェクト
#' @param refs_base est.MSYから得られる管理基準値の表
#' @encoding UTF-8
#'
#' @export
#'

plot_kobe_gg <- plot_kobe <- function(vpares,refs_base,roll_mean=1,
                                      category=4,# 削除予定オプション
                                      Btarget=c("Btarget0"),
                                      Blimit=c("Blimit0"),
                                      Blow=c("Blow0"), # 削除予定オプション
                                      Bban=c("Bban0"),
                                      write.vline=TRUE,
                                      ylab.type="U", # or "U"
                                      labeling.year=NULL,
                                      RP.label=c("目標管理基準値","限界管理基準値","禁漁水準"),
                                      refs.color=c("#00533E","#edb918","#C73C2E"),
                                      Fratio=NULL,
                                      yscale=1.2,xscale=1.2,
                                      HCR.label.position=c(1,1),
                                      beta=NULL,
                                      plot.year="all"){

  target.RP <- derive_RP_value(refs_base,Btarget)
  limit.RP <- derive_RP_value(refs_base,Blimit)
  low.RP <- derive_RP_value(refs_base,Blow)
  ban.RP <- derive_RP_value(refs_base,Bban)

  low.ratio <- low.RP$SSB/target.RP$SSB
  limit.ratio <- limit.RP$SSB/target.RP$SSB
  ban.ratio <- ban.RP$SSB/target.RP$SSB

  vpa_tb <- convert_vpa_tibble(vpares)
  UBdata <- vpa_tb %>% dplyr::filter(stat=="U" | stat=="SSB") %>%
    spread(key=stat,value=value) %>%
    mutate(Uratio=RcppRoll::roll_mean(U/target.RP$U,n=roll_mean,fill=NA,align="right"),
           Bratio=RcppRoll::roll_mean(SSB/target.RP$SSB,n=roll_mean,fill=NA,align="right")) %>%
    arrange(year)
  if(ylab.type=="F") UBdata <- UBdata %>% mutate(Uratio=Fratio)

  if(is.null(labeling.year)){
    years <- unique(UBdata$year)
    labeling.year <- c(years[years%%5==0],max(years))
  }

  UBdata <- UBdata %>%
      mutate(year.label=ifelse(year%in%labeling.year,year,""),
             year_group=1)

  if(plot.year[1]!="all") {
      diff.year <- plot.year[which(diff(plot.year)>1)+1] 
      UBdata <- UBdata %>% filter(year %in% plot.year) 

      for(i in 1:length(diff.year)){
          UBdata <- UBdata %>%
              mutate(year_group = ifelse(year >= diff.year[i], year_group+1, year_group))
      }
  }

  max.B <- max(c(UBdata$Bratio,xscale),na.rm=T)
  max.U <- max(c(UBdata$Uratio,yscale),na.rm=T)

    red.color <- "indianred1" # rgb(238/255,121/255,72/255)
    yellow.color <- "khaki1" # rgb(245/255,229/255,107/255)
    green.color <- "olivedrab2" # rgb(175/255,209/255,71/255) #"olivedrab2"#rgb(58/255,180/255,131/255)
    
  g4 <- ggplot(data=UBdata) +theme(legend.position="none")+
    geom_polygon(data=tibble(x=c(-1,1,1,-1),
                             y=c(-1,-1,1,1)),
                 aes(x=x,y=y),fill=yellow.color)+
    geom_polygon(data=tibble(x=c(1,20,20,1),
                             y=c(-1,-1,1,1)),
                 aes(x=x,y=y),fill=green.color)+
    geom_polygon(data=tibble(x=c(1,20,20,1),
                             y=c(1,1,20,20)),
                 aes(x=x,y=y),fill=yellow.color)+
    geom_polygon(data=tibble(x=c(-1,1,1,-1),
                             y=c(1,1,20,20)),
                 aes(x=x,y=y),fill=red.color) +
    geom_polygon(data=tibble(x=c(-1,1,1,-1),
                             y=c(-1,-1,1,1)),aes(x=x,y=y),fill=yellow.color)

  if(write.vline){
    g4 <- g4 + geom_vline(xintercept=c(1,limit.ratio,ban.ratio),color=refs.color,lty="41",lwd=0.7)+
      ggrepel::geom_label_repel(data=tibble(x=c(1,limit.ratio,ban.ratio),
                                            y=max.U*0.85,
                                            label=RP.label),
                                aes(x=x,y=y,label=label),
                                direction="x",nudge_y=max.U*0.9,size=11*0.282)
  }

  if(!is.null(beta)){
    ### HCRのプロット用の設定
    #Setting of the function to multiply current F for SSB
    multi2currF = function(x){
      if(x > limit.ratio) {multi2currF=beta}
      else if (x < ban.ratio) {multi2currF=0}
      else { multi2currF = beta*(x - ban.ratio)/(limit.ratio - ban.ratio) }
      return(multi2currF)
    }

    #Function setting for drawing.
    h=Vectorize(multi2currF)
    ####
    x.pos <- max.B*HCR.label.position[1]
    y.pos <- multi2currF(1.05)*HCR.label.position[2]
    g4 <- g4+stat_function(fun = h,lwd=1.5,color="black",n=5000)+
      annotate("text",x=x.pos,y=y.pos,
               label=str_c("漁獲管理規則\n(β=",beta,")"))
  }

  g4 <- g4 +
    geom_path(mapping=aes(x=Bratio,y=Uratio,group=year_group)) +
    geom_point(mapping=aes(x=Bratio,y=Uratio,group=year_group),shape=21,fill="white") +
    coord_cartesian(xlim=c(0,max.B*1.1),ylim=c(0,max.U*1.15),expand=0) +
    ylab("漁獲割合の比 (U/Umsy)") + xlab("親魚量の比 (SB/SBmsy)")  +
    ggrepel::geom_text_repel(#data=dplyr::filter(UBdata,year%in%labeling.year),
      aes(x=Bratio,y=Uratio,label=year.label),
      size=4,box.padding=0.5,segment.color="gray")

  if(ylab.type=="F"){
    g4 <- g4 + ylab("漁獲圧の比 (F/Fmsy)")
  }

  g4 <- g4 + theme_SH()

  return(g4)
}

#' 将来予測の複数の結果をggplotで重ね書きする
#'
#' @param vpares VPAの結果のオブジェクト
#' @param future.list 将来予測の結果をリストで並べたもの
#' @param n_example 個々のシミュレーションの例を示す数
#' @param width_example 個々のシミュレーションをプロットする場合の線の太さ (default=0.7)
#' @param future.replicate どのreplicateを選ぶかを選択する。この場合n_exampleによる指定は無効になる
#' @encoding UTF-8
#' @export

plot_futures <- function(vpares,
                         future.list=NULL,
                         future.name=names(future.list),
                         future_tibble=NULL,
                         CI_range=c(0.1,0.9),
                         maxyear=NULL,
                         is.plot.CIrange=TRUE,
                         what.plot=c("Recruitment","SSB","biomass","catch","beta_gamma","U","Fratio"),
                         biomass.unit=1,
                         number.unit=1,
                         number.name="",
                         RP_name=c("Btarget","Blimit","Bban"),
                         Btarget=0,Blimit=0,Bban=0,#Blow=0,
                         MSY=0,Umsy=0,
                         SPRtarget=NULL,
                         exclude.japanese.font=FALSE, # english version
                         n_example=3, # number of examples
                         example_width=0.7, # line width of examples
                         future.replicate=NULL,
                         seed=1, # seed for selecting the above example
                         legend.position="top",
                         font.size=18,
                         ncol=3
){

  col.SBtarget <- "#00533E"
  col.SBlim <- "#edb918"
  col.SBban <- "#C73C2E"
  col.MSY <- "black"
  col.Ftarget <- "#714C99"
  col.betaFtarget <- "#505596"

  for(i in 1:length(future.list)){
    if(class(future.list[[i]])=="future_new")
      future.list[[i]] <- format_to_old_future(future.list[[i]])
    det.run <- FALSE
  }

  if(!isTRUE(exclude.japanese.font)){
    junit <- c("","十","百","千","万")[log10(biomass.unit)+1]

    rename_list <- tibble(stat=c("Recruitment","SSB","biomass","catch","beta_gamma","U","Fratio"),
                          jstat=c(str_c("加入尾数(",number.name,"尾)"),
                                  str_c("親魚量 (",junit,"トン)"),
                                  str_c("資源量 (",junit,"トン)"),
                                  str_c("漁獲量 (",junit,"トン)"),
                                  "beta_gamma(F/Fmsy)",
                                  "漁獲割合(%)",
                                  "漁獲圧の比(F/Fmsy)"))
  }
  else{
    junit <- c("","10","100","1000","10,000")[log10(biomass.unit)+1]
    #    require(tidyverse,quietly=TRUE)

    rename_list <- tibble(stat=c("Recruitment","SSB","biomass","catch","beta_gamma","U","Fratio"),
                          jstat=c(str_c("Recruits(",number_name,"fish)"),
                                  str_c("SB (",junit,"MT)"),
                                  str_c("Biomass (",junit,"MT)"),
                                  str_c("Catch (",junit,"MT)"),
                                  "multiplier to Fmsy",
                                  "Catch/Biomass (U)",
                                  "F ratio (F/Fmsy)"))
  }

  # define unit of value
  rename_list <- rename_list %>%
    mutate(unit=dplyr::case_when(stat%in%c("SSB","biomass","catch") ~ biomass.unit,
                                 stat%in%c("Recruitment")           ~ number.unit,
                                 stat%in%c("U")                     ~ 0.01,
                                 TRUE                               ~ 1))

  rename_list <- rename_list %>% dplyr::filter(stat%in%what.plot)

  if(!is.null(future.list)){
    if(is.null(future.name)) future.name <- str_c("s",1:length(future.list))
    names(future.list) <- future.name
  }
  else{
    if(is.null(future.name)) future.name <- str_c("s",1:length(unique(future_tibble$HCR_name)))
  }

  if(is.null(future_tibble)) future_tibble <- purrr::map_dfr(future.list,convert_future_table,.id="scenario")

  future_tibble <-
    future_tibble %>%
    dplyr::filter(stat%in%rename_list$stat) %>%
    mutate(stat=factor(stat,levels=rename_list$stat)) %>%
    left_join(rename_list) %>%
    mutate(value=value/unit)

  if(is.null(future.replicate)){
    set.seed(seed)
    future.replicate <- sample(2:max(future_tibble$sim),n_example)
  }
  future.example <- future_tibble %>%
    dplyr::filter(sim%in%future.replicate) %>%
    group_by(sim,scenario)

  if(is.null(maxyear)) maxyear <- max(future_tibble$year)

  min.age <- as.numeric(rownames(vpares$naa)[1])
  vpa_tb <- convert_vpa_tibble(vpares,SPRtarget=SPRtarget) %>%
    mutate(scenario=type,year=as.numeric(year),
           stat=factor(stat,levels=rename_list$stat),
           mean=value,sim=0)%>%
    dplyr::filter(stat%in%rename_list$stat) %>%
    left_join(rename_list) %>%
    mutate(value=value/unit,mean=mean/unit)

  # 将来と過去をつなげるためのダミーデータ
  tmp <- vpa_tb %>% group_by(stat) %>%
    summarise(value=tail(value[!is.na(value)],n=1,na.rm=T),year=tail(year[!is.na(value)],n=1,na.rm=T),sim=0)
  future.dummy <- purrr::map_dfr(future.name,function(x) mutate(tmp,scenario=x))

  org.warn <- options()$warn
  options(warn=-1)
  future_tibble <-
    bind_rows(future_tibble,vpa_tb,future.dummy) %>%
    mutate(stat=factor(stat,levels=rename_list$stat)) %>%
    mutate(scenario=factor(scenario,levels=c(future.name,"VPA"))) #%>%
  #        mutate(value=ifelse(stat%in%c("beta_gamma","U"),value,value/biomass.unit))

  future_tibble.qt <-
    future_tibble %>% group_by(scenario,year,stat) %>%
    summarise(low=quantile(value,CI_range[1],na.rm=T),
              high=quantile(value,CI_range[2],na.rm=T),
              median=median(value,na.rm=T),
              mean=mean(value))

  # make dummy for y range
  dummy <- future_tibble %>% group_by(stat) %>% summarise(max=max(value)) %>%
    mutate(value=0,year=min(future_tibble$year,na.rm=T)) %>%
    select(-max)

  dummy2 <- future_tibble %>% group_by(stat) %>%
    summarise(max=max(quantile(value,CI_range[2],na.rm=T))) %>%
    mutate(value=max*1.1,
           year=min(future_tibble$year,na.rm=T)) %>%
    select(-max)

  future_tibble.qt <- left_join(future_tibble.qt,rename_list) %>%
    mutate(jstat=factor(jstat,levels=rename_list$jstat))

  dummy     <- left_join(dummy,rename_list,by="stat") %>% dplyr::filter(!is.na(stat))
  dummy2    <- left_join(dummy2,rename_list,by="stat") %>% dplyr::filter(!is.na(stat))

  if("SSB" %in% what.plot){
    ssb_RP <- tibble(jstat = dplyr::filter(rename_list, stat == "SSB") %>%
                       dplyr::pull(jstat),
                     value = c(Btarget, Blimit, Bban) / biomass.unit,
                     RP_name = RP_name)
  }
  if("catch" %in% what.plot){
    catch_RP <- tibble(jstat=dplyr::filter(rename_list, stat == "catch") %>%
                         dplyr::pull(jstat),
                       value=MSY/biomass.unit,
                       RP_name="MSY")
  }
  if("U" %in% what.plot){
    U_RP <- tibble(jstat=dplyr::filter(rename_list, stat == "U") %>%
                     dplyr::pull(jstat),
                   value=Umsy,
                   RP_name="U_MSY")
  }

  options(warn=org.warn)

  g1 <- future_tibble.qt %>% dplyr::filter(!is.na(stat)) %>%
    ggplot()

  if(isTRUE(is.plot.CIrange)){
      g1 <- g1+
      geom_line(data=dplyr::filter(future_tibble.qt,!is.na(stat) & scenario!="VPA" & year <= maxyear),
                  mapping=aes(x=year,y=high,lty=scenario,color=scenario))+
      geom_line(data=dplyr::filter(future_tibble.qt,!is.na(stat) & scenario!="VPA" & year <= maxyear),
                  mapping=aes(x=year,y=low,lty=scenario,color=scenario))+    
      geom_ribbon(data=dplyr::filter(future_tibble.qt,!is.na(stat) & scenario!="VPA" & year <= maxyear),
                  mapping=aes(x=year,ymin=low,ymax=high,fill=scenario),alpha=0.4)+
      geom_line(data=dplyr::filter(future_tibble.qt,!is.na(stat) & scenario!="VPA" & year <= maxyear),
                mapping=aes(x=year,y=mean,color=scenario),lwd=1)
  }
  #    else{
  #        g1 <- g1+
  #            geom_line(data=dplyr::filter(future_tibble.qt,!is.na(stat) & scenario=="VPA"),
  #                      mapping=aes(x=year,y=mean,color=scenario),lwd=1)#+
  #    }

  g1 <- g1+
    geom_blank(data=dummy,mapping=aes(y=value,x=year))+
    geom_blank(data=dummy2,mapping=aes(y=value,x=year))+
    #theme_bw(base_size=font.size) +
    #        coord_cartesian(expand=0)+
    scale_y_continuous(expand=expand_scale(mult=c(0,0.05)))+
    facet_wrap(~factor(jstat,levels=rename_list$jstat),scales="free_y",ncol=ncol)+
    xlab("年")+ylab("")+ labs(fill = "",linetype="",color="")+
    xlim(min(future_tibble$year),maxyear)

  if("SSB" %in% what.plot){
    g1 <- g1 + geom_hline(data = ssb_RP,
                          aes(yintercept = value, linetype = RP_name),
                          color = c(col.SBtarget, col.SBlim, col.SBban))
  }

  if("catch" %in% what.plot){
    g1 <- g1 + geom_hline(data = catch_RP,
                          aes(yintercept = value, linetype = RP_name),
                          color = c(col.MSY))
  }

  if("U" %in% what.plot){
    g1 <- g1 + geom_hline(data = U_RP,
                          aes(yintercept = value, linetype = RP_name),
                          color = c(col.MSY))
  }

  if(n_example>0){
    if(n_example>1){
      g1 <- g1 + geom_line(data=dplyr::filter(future.example,year <= maxyear),
                           mapping=aes(x=year,y=value,
                                       alpha=factor(sim),
                                       color=scenario),
                           lwd=example_width)
    }
    else{
      g1 <- g1 + geom_line(data=dplyr::filter(future.example,year <= maxyear),
                           mapping=aes(x=year,y=value,
                                       color=scenario),
                           lwd=example_width)
    }
    g1 <- g1+scale_alpha_discrete(guide=FALSE)
  }

  g1 <- g1 + guides(lty=guide_legend(ncol=3),
                    fill=guide_legend(ncol=3),
                    col=guide_legend(ncol=3))+
    theme_SH(base_size=font.size,legend.position=legend.position)+
    scale_color_hue(l=40)+
    labs(caption = str_c("(塗り:", CI_range[1]*100,"-",CI_range[2]*100,
                         "%信頼区間, 太い実線: 平均値",
                         ifelse(n_example>0,", 細い実線: シミュレーションの1例)",")")
    ))

  g1 <- g1 +
    geom_line(data=dplyr::filter(future_tibble.qt,!is.na(stat) & scenario=="VPA"),
              mapping=aes(x=year,y=mean),lwd=1,color="black")# VPAのプロット
  return(g1)
}

#' F currentをプロットする
#'
#' @param vpares VPAの結果のオブジェクト
#' @encoding UTF-8
#'
#' @export

plot_Fcurrent <- function(vpares,
                          Fcurrent=NULL,
                          year.range=NULL){

  if(is.null(year.range)) year.range <- min(as.numeric(colnames(vpares$naa))):max(as.numeric(colnames(vpares$naa)))
  vpares_tb <- convert_vpa_tibble(vpares)

  faa_history <- vpares_tb %>%
    dplyr::filter(stat=="fishing_mortality", year%in%year.range) %>%
    mutate(F=value,year=as.character(year),type="History") %>%
    select(-stat,-sim,-value) %>%
    group_by(year) %>%
    dplyr::filter(!is.na(F)) %>%
    mutate(Year=as.numeric(year)) %>%
    mutate(age_name=ifelse(max(age)==age,str_c(age,"+"),age))

  if(is.null(Fcurrent)){
    fc_at_age_current <- vpares$Fc.at.age
  }
  else{
    fc_at_age_current <- Fcurrent
  }
  fc_at_age_current <- tibble(F=fc_at_age_current,age=as.numeric(rownames(vpares$naa)),
                              year="0",type="currentF") %>%
    dplyr::filter(!is.na(F)) %>%
    mutate(age_name=ifelse(max(age)==age,str_c(age,"+"),age))

  pal <- c("#3B9AB2", "#56A6BA", "#71B3C2", "#9EBE91", "#D1C74C",
           "#E8C520", "#E4B80E", "#E29E00", "#EA5C00", "#F21A00")
  g <- faa_history  %>% ggplot() +
    geom_path(aes(x=age_name,y=F,color=Year,group=Year),lwd=1.5) +
    scale_color_gradientn(colors = pal)+
    geom_path(data=fc_at_age_current,
              mapping=aes(x=age_name,y=F,group=type),color="black",lwd=1.5,lty=1)+
    geom_point(data=fc_at_age_current,
               mapping=aes(x=age_name,y=F,shape=type),color="black",size=3)+
    coord_cartesian(ylim=c(0,max(faa_history$F,na.rm=T)))+
    ##                        xlim=range(as.numeric(faa_history$age_name,na.rm=T))+c(-0.5,0.5)
    #                        )+
    xlab("年齢")+ylab("漁獲係数(F)")+theme_SH(legend.position="right")+
    scale_shape_discrete(name="", labels=c("F current"))

  return(g)
}


library(ggplot2)

#Setting parameter values.
#SBtarget <- 250
#SBban <- 0.1*SBtarget
#SBlim <- 0.4*SBtarget
#Ftarget <-1.5
#beta <- 0.8

#' HCRを書く
#'
#' @param SBtarget 目標管理基準値
#' @param SBlim    限界管理基準値
#' @param SBlim    禁漁水準
#' @param Ftarget  Ftarget
#' @param is.text ラベルを記入するかどうか（FALSEにすると後で自分で書き換えられる）
#' @encoding UTF-8
#'
#' @export

plot_HCR <- function(SBtarget,SBlim,SBban,Ftarget,
                     Fcurrent=-1,
                     biomass.unit=1,
                     beta=0.8,col.multi2currf="black",col.SBtarget="#00533E",
                     col.SBlim="#edb918",col.SBban="#C73C2E",col.Ftarget="black",
                     col.betaFtarget="gray",is.text = TRUE,
                     RP.label=c("目標管理基準値","限界管理基準値","禁漁水準")){

  # Arguments; SBtarget,SBlim,SBban,Ftarget,beta,col.multi2currf,col.SBtarget,col.SBlim,col.SBban,col.Ftarget,col.betaFtarget.
  # col.xx means the line color for xx on figure.
  # beta and col.xx have default values.
  # Default setting for beta = 0.8, therefore define this as (beta <-0.8) outside this function if the beta-value changes frequently.
  # Default color setting for each parameter; Function(col.multi2currf="blue"), SBtarget(col.SBtarget = "green"), SBlimit(col.SBlim = "yellow"),SBban(col.SBban = "red"),Ftarget(col.Ftarget = "black"), β Ftarget(col.betaFtarget = "gray")

  junit <- c("","十","百","千","万")[log10(biomass.unit)+1]
  SBtarget <- SBtarget/biomass.unit
  SBlim <- SBlim/biomass.unit
  SBban <- SBban/biomass.unit

  #Setting of the function to multiply current F for SSB
  multi2currF = function(x){
    if(x > SBlim) {multi2currF=beta*Ftarget}
    else if (x < SBban) {multi2currF=0}
    else { multi2currF = (x - SBban)* beta*Ftarget/(SBlim - SBban) }
    return(multi2currF)
  }

  #Function setting for drawing.
  h=Vectorize(multi2currF)

  #Drawing of the funciton by ggplot2
  ggplct <- ggplot(data.frame(x = c(0,1.5*SBtarget),y= c(0,1.5*Ftarget)), aes(x=x)) +
    stat_function(fun = h,lwd=1.5,color=col.multi2currf, n=5000)
  g <- ggplct  + geom_vline(xintercept = SBtarget, size = 0.9, linetype = "41", color = col.SBtarget) +
    geom_vline(xintercept = SBlim, size = 0.9, linetype = "41", color = col.SBlim) +
    geom_vline(xintercept = SBban, size = 0.9, linetype = "41", color = col.SBban) +
    geom_hline(yintercept = Ftarget, size = 0.9, linetype = "43", color = col.Ftarget) +
    geom_hline(yintercept = beta*Ftarget, size = 0.7, linetype = "43", color = col.betaFtarget) +
    labs(x = str_c("親魚量 (",junit,"トン)"),y = "漁獲圧の比(F/Fmsy)",color = "") +
    theme_bw(base_size=12)+
    theme(legend.position="none",panel.grid = element_blank())+
    stat_function(fun = h,lwd=1,color=col.multi2currf)

  if(Fcurrent>0){
    g <- g+geom_hline(yintercept = Fcurrent, size = 0.7, linetype = 1, color = "gray")+
      geom_label(label="Fcurrent", x=SBtarget*1.1, y=Fcurrent)

  }

  if(is.text) {
    RPdata <- tibble(RP.label=RP.label, value=c(SBtarget, SBlim, SBban), y=c(1.1,1.05,1.05))
    g <- g + ggrepel::geom_label_repel(data=RPdata, 
                                mapping=aes(x=value, y=y, label=RP.label), 
                                box.padding=0.5, nudge_y=1) +
      geom_label(label="Fmsy", x=SBtarget*1.3, y=Ftarget)+
      geom_label(label=str_c(beta,"Fmsy"), x=SBtarget*1.3, y=beta*Ftarget)+
        ylim(0,1.3)
  }

  return(g)

  #Drawing in a classical way
  # curve(h,
  #       xlim=c(0,2*SBtarget),  # range for x-axis is from 0 to 2*SBtarget
  #       ylim=c(0,1.2*Ftarget), # range for y-axis is from 0 to 1.2*Ftarget
  #       main="",
  #       xlab="SSB(×1000[t])",
  #       ylab="multipliyer to current F",
  #       lwd=2,
  #       col=col.multi2currf
  # )
  #Adding extention lines.
  # abline(v=SBtarget,lty=2,lwd=2,col=col.SBtarget)
  # abline(v=SBlim,lty=2,lwd=2,col=col.SBlim)
  # abline(v=SBban,lty=2,lwd=2,col=col.SBban)
  # abline(h=Ftarget,lty=2,col=col.Ftarget)
  # abline(h=beta*Ftarget,lty=3,col=col.betaFtarget)

  #Display legends at bottom right of the figure.
  # legend("bottomright",
  #        legend=c("SBtarget","SBlimit","SBban","Ftarget","β Ftarget"),
  #        lty=c(2,2,2,2,3),
  #        lwd=c(2,2,2,1,1),
  #        col=c(col.SBtarget, "yellow", "red","black","gray"),
  #        bty="n"
  # )

  #Setting each legend manually.
  # legend(SBtarget, 1.1*Ftarget,legend='SBtarget',bty="n")
  # legend(SBlim, 1.1*Ftarget, legend='SBlimit',bty="n")
  # legend(SBban, 1.1*Ftarget, legend='SBban',bty="n")
  # legend(0, Ftarget, legend='Ftarget',bty="n")
  # legend(0, beta*Ftarget, legend='β Ftarget',bty="n")

}

#' 縦軸が漁獲量のHCRを書く（traceの結果が必要）
#'
#' @param trace 
#' @param fout 将来予測のアウトプット（finputがない場合)
#' @param Fvector Fのベクトル
#' @encoding UTF-8
#' @export

plot_HCR_by_catch <- function(trace,
                              fout0.8,
                              SBtarget,SBlim,SBban,Fmsy_vector,MSY,
                              M_vector,
                              biomass.unit=1,
                              beta=0.8,col.multi2currf="black",col.SBtarget="#00533E",
                              col.SBlim="#edb918",col.SBban="#C73C2E",col.Ftarget="black",
                              col.betaFtarget="gray",is.text = TRUE,
                              Pope=TRUE,
                              RP.label=c("目標管理基準値","限界管理基準値","禁漁水準")){
    # 本当は途中までplot_HCRと統合させたい
    junit <- c("","十","百","千","万")[log10(biomass.unit)+1]    
    biomass_comp <- trace %>% dplyr::select(starts_with("TB-mean-"))
    biomass_comp <- biomass_comp[,Fmsy_vector>0]
    M_vector <- M_vector[Fmsy_vector>0]
    Fmsy_vector <- Fmsy_vector[Fmsy_vector>0]
    
    calc_catch <- function(B, M, Fvec, Pope=TRUE){
        if(isTRUE(Pope)){
            total.catch <- B*(1-exp(-Fvec))*exp(-M/2) 
        }
        else{
            total.catch <- B*(1-exp(-Fvec-M))*Fvec/(Fvec+M) 
        }
        return(sum(total.catch))
    }
    
    n <- nrow(trace)
    gamma <- HCR_default(as.numeric(trace$ssb.mean),
                         Blimit=rep(SBlim,n),Bban=rep(SBban,n),beta=rep(beta,n))
    F_matrix <- outer(gamma, Fmsy_vector)
    trace$catch_HCR <- purrr::map_dbl(1:nrow(trace), function(x) 
        calc_catch(biomass_comp[x,],M_vector, F_matrix[x,], Pope=Pope))

    trace <- trace %>% dplyr::arrange(ssb.mean) %>%
        dplyr::filter(ssb.mean < SBtarget*1.5)
    
    g <- trace %>%
        ggplot()+
        geom_line(aes(x=ssb.mean/biomass.unit,y=catch_HCR/biomass.unit),lwd=1)+
        theme_SH()+
        geom_vline(xintercept = SBtarget/biomass.unit, size = 0.9, linetype = "41", color = col.SBtarget) +
        geom_vline(xintercept = SBlim/biomass.unit, size = 0.9, linetype = "41", color = col.SBlim) +
        geom_vline(xintercept = SBban/biomass.unit, size = 0.9, linetype = "41", color = col.SBban) +
  #      geom_hline(yintercept = MSY/biomass.unit,color="gray")+
        xlab(str_c("親魚量 (",junit,"トン)"))+
        ylab(str_c("漁獲量 (",junit,"トン)"))

    if(is.text) {
        RPdata <- tibble(RP.label=RP.label, value=c(SBtarget, SBlim, SBban)/biomass.unit,
                         y=rep(max(trace$catch_HCR)*0.9,3)/biomass.unit)
        g <- g + ggrepel::geom_label_repel(data=RPdata, 
                                           mapping=aes(x=value, y=y, label=RP.label), 
                                           box.padding=0.5, nudge_y=1) #+
        # geom_label(label="MSY", x=SBtarget*1.4/biomass.unit, y=MSY/biomass.unit)
        #      geom_label(label=str_c(beta,"Fmsy"), x=SBtarget*1.3, y=beta*Ftarget)+
        #        ylim(0,1.3)
    }
    
  
}


# test plot
#Fig_Fish_Manage_Rule(SBtarget,SBlim,SBban,Ftarget,col.multi2currf = "#093d86", col.SBtarget = "#00533E", col.SBlim = "#edb918",col.SBban = "#C73C2E",col.Ftarget = "#714C99", col.betaFtarget = "#505596")
# function;ruri-rio, sbtarget;moegi-iro, sblim;koki-ki; sbban;hi-iro, ftarget;sumire-iro, betaftarget;kikyou-iro

#' MSYを達成するときの\%SPRを計算する
#'
#' @param finput 将来予測インプット
#' @param fout 将来予測のアウトプット（finputがない場合)
#' @param Fvector Fのベクトル
#' @encoding UTF-8
#' @export
calc_perspr <- function(finput=NULL,
                        fout=NULL,
                        res_vpa=NULL,
                        Fvector,
                        Fmax=10,
                        max.age=Inf,
                        target.col=NULL
){
    if(!is.null(finput)){
    # MSYにおける将来予測計算をやりなおし
    finput$outtype <- "FULL"
    fout.tmp <- do.call(future.vpa,finput)
    res_vpa <- finput$res0
  }
  else{
    fout.tmp <- fout
  }
  # 生物パラメータはその将来予測で使われているものを使う
  if(is.null(target.col)){
    waa.tmp           <- fout.tmp$waa[,dim(fout.tmp$waa)[[2]],1]
    waa.catch.tmp <- fout.tmp$waa.catch[,dim(fout.tmp$waa.catch)[[2]],1]
    maa.tmp           <- fout.tmp$maa[,dim(fout.tmp$maa)[[2]],1]
    M.tmp                <- fout.tmp$M[,dim(fout.tmp$M)[[2]],1]
  }
  else{
    waa.tmp           <- fout.tmp$waa[,target.col,1]
    waa.catch.tmp <- fout.tmp$waa.catch[,target.col,1]
    maa.tmp           <- fout.tmp$maa[,target.col,1]
    M.tmp               <- fout.tmp$M[,target.col,1]
  }

  # 緊急措置。本来ならどこをプラスグループとして与えるかを引数として与えないといけない
  allsumpars <- waa.tmp+waa.catch.tmp+maa.tmp+M.tmp
  waa.tmp <- waa.tmp[allsumpars!=0]
  waa.catch.tmp <- waa.catch.tmp[allsumpars!=0]
  maa.tmp <- maa.tmp[allsumpars!=0]
  M.tmp <- M.tmp[ allsumpars!=0]     
  Fvector <- Fvector %>%  as.numeric()
  Fvector <- Fvector[allsumpars!=0]
  ## ここまで緊急措置
  
  # SPRを計算
  spr.current <- ref.F(res_vpa,Fcurrent=Fvector,
                       waa=waa.tmp,
                       waa.catch=waa.catch.tmp,pSPR=NULL,
                       maa=maa.tmp,M=M.tmp,rps.year=as.numeric(colnames(res_vpa$naa)),
                       F.range=c(seq(from=0,to=ceiling(max(res_vpa$Fc.at.age,na.rm=T)*Fmax),
                                     length=101),max(res_vpa$Fc.at.age,na.rm=T)),
                       plot=FALSE,max.age=max.age)$currentSPR$perSPR
  spr.current
}

#' kobeIItable から任意の表を指名して取り出す
#'
#' @param kobeII_table \code{make_kobeII_table}の出力
#' @param name \code{kobeII_table}の要素名
#'
#' @encoding UTF-8
pull_var_from_kobeII_table <- function(kobeII_table, name) {
  table <- kobeII.table[[name]]
  table %>%
    dplyr::arrange(desc(beta)) %>%
    dplyr::select(-HCR_name, -stat_name)
}

#' kobeIItableから取り出した表を整形
#'
#' - 報告書に不要な列を除去する
#' - 単位を千トンに変換
#' @param beta_table \code{pull_var_from_kobeII_table}で取得した表
#' @param divide_by 表の値をこの値で除する．トンを千トンにする場合には1000
#' @param round TRUEなら値を丸める．漁獲量は現状整数表示なのでデフォルトはTRUE
format_beta_table <- function(beta_table, divide_by = 1, round = TRUE) {
  beta   <- beta_table %>%
    dplyr::select(beta) %>%
    magrittr::set_colnames("\u03B2") # greek beta in unicode
  values <- beta_table %>%
    dplyr::select(-beta) / divide_by
  if (round == TRUE) return(cbind(beta, round(values)))
  cbind(beta, values)
}

#' 値の大小に応じて表の背景にグラデーションをつける
#' @param beta_table \code{format_beta_table}で整形したβの表
#' @param color 表の背景となる任意の色
colorize_table <- function(beta_table, color) {
  beta_table %>%
    formattable::formattable(list(formattable::area(col = -1) ~
                                    formattable::color_tile("white", color)))
}

#' 表を画像として保存
#'
#' # @inheritParams \code{\link{formattable::as.htmlwidget}}
#' # @inheritParams \code{\link{htmltools::html_print}}
#' # @inheritParams \code{\link{webshot::webshot}}
#' @param table ファイルとして保存したい表
#' @examples
#' \dontrun{
#' your_table %>%
#'  export_formattable(file = "foo.png")
#' }
#' @export
export_formattable <- function(table, file, width = "100%", height = NULL,
                               background = "white", delay = 0.1) {
  widget <- formattable::as.htmlwidget(table, width = width, height = height)
  path   <- htmltools::html_print(widget, background = background, viewer = NULL)
  url    <- paste0("file:///", gsub("\\\\", "/", normalizePath(path)))
  webshot::webshot(url,
                   file = file,
                   selector = ".formattable_widget",
                   delay = delay)
}

#' kobeIItableから任意の表を取得し画像として保存
#'
#' @inheritParams \code{\link{pull_var_from_kobeII_table}}
#' @inheritParams \code{\link{format_beta_table}}
#' @inheritParams \code{\link{colorize_table}}
#' @inheritParams \code{\link{export_formattable}}
export_kobeII_table <- function(name, divide_by, color, fname, kobeII_table) {
  kobeII_table %>%
    pull_var_from_kobeII_table(name) %>%
    format_beta_table(divide_by = divide_by) %>%
    colorize_table(color) %>%
    export_formattable(fname)
}

#' β調整による管理効果を比較する表を画像として一括保存
#'
#' @inheritParams \code{\link{pull_var_from_kobeII_table}}
#' @param fname_ssb 「平均親魚量」の保存先ファイル名
#' @param fname_catch 「平均漁獲量」の保存先ファイル名
#' @param fname_ssb_above_target 「親魚量が目標管理基準値を上回る確率」の保存先ファイル名
#' @param fname_ssb_above_limit 「親魚量が限界管理基準値を上回る確率」の保存先ファイル名
#' @examples
#' \dontrun{
#' export_kobeII_tables(kobeII.table)
#' }
#' @export
export_kobeII_tables <- function(kobeII_table,
                                 fname_ssb = "tbl_ssb.png",
                                 fname_catch = "tbl_catch.png",
                                 fname_ssb_above_target = "tbl_ssb>target.png",
                                 fname_ssb_above_limit = "tbl_ssb>limit.png") {
  blue   <- "#96A9D8"
  green  <- "#B3CE94"
  yellow <- "#F1C040"

  purrr::pmap(list(name = c("ssb.mean", "catch.mean",
                            "prob.over.ssbtarget", "prob.over.ssblimit"),
                   divide_by = c(1000, 1000, 1, 1),
                   color = c(blue, green, yellow, yellow),
                   fname = c(fname_ssb, fname_catch,
                             fname_ssb_above_target, fname_ssb_above_limit)),
              .f = export_kobeII_table,
              kobeII_table = kobeII_table)
}

#' 会議用の図のフォーマット
#'
#' @export
#'

theme_SH <- function(legend.position="none",base_size=12){
  theme_bw(base_size=base_size) +
    theme(panel.grid = element_blank(),
          axis.text.x=element_text(size=11,color="black"),
          axis.text.y=element_text(size=11,color="black"),
          axis.line.x=element_line(size= 0.3528),
          axis.line.y=element_line(size= 0.3528),
          legend.position=legend.position)
}

#' 会議用の図の出力関数（大きさ・サイズの指定済）：通常サイズ
#'
#' @export
#'

ggsave_SH <- function(...){
  ggsave(width=150,height=85,dpi=600,units="mm",...)
}

#' 会議用の図の出力関数（大きさ・サイズの指定済）：大きいサイズ
#'
#' @export
#'

ggsave_SH_large <- function(...){
  ggsave(width=150,height=120,dpi=600,units="mm",...)
}

#' fit.SRregimeの結果で得られた再生産関係をプロットするための関数
#'
#' レジームごとの観察値と予測線が描かれる
#' @param resSRregime \code{fit.SRregime}の結果
#' @param xscale X軸のスケーリングの値（親魚量をこの値で除す）
#' @param xlabel X軸のラベル
#' @param yscale Y軸のスケーリングの値（加入量をこの値で除す）
#' @param ylabel Y軸のラベル
#' @param labeling.year ラベルに使われる年
#' @param show.legend 凡例を描くかどうか
#' @param legend.title 凡例のタイトル（初期設定は\code{"Regime"}）
#' @param regime.name 凡例に描かれる各レジームの名前（レジームの数だけ必要）
#' @param base_size \code{ggplot}のベースサイズ
#' @param add.info \code{AICc}や\code{regime.year}, \code{regime.key}などの情報を加えるかどうか
#' @param use.fit.SR パラメータの初期値を決めるのに\code{frasyr::fit.SR}を使う（時間の短縮になる）
#' @examples
#' \dontrun{
#' data(res_vpa)
#' SRdata <- get.SRdata(res_vpa)
#' resSRregime <- fit.SRregime(SRdata, SR="HS", method="L2",
#'                             regime.year=c(1977,1989), regime.key=c(0,1,0),
#'                             regime.par = c("a","b","sd")[2:3])
#' g1 <- SRregime_plot(resSRregime, regime.name=c("Low","High"))
#' g1
#' }
#' @encoding UTF-8
#' @export
#'

SRregime_plot <- function (SRregime_result,xscale=1000,xlabel="SSB",yscale=1,ylabel="R",
                           labeling.year = NULL, show.legend = TRUE, legend.title = "Regime",regime.name = NULL,
                           base_size = 16, add.info = TRUE) {
  pred_data = SRregime_result$pred %>% mutate(Category = "Pred")
  obs_data = select(SRregime_result$pred_to_obs, -Pred, -resid) %>% mutate(Category = "Obs")
  combined_data = full_join(pred_data, obs_data) %>%
    mutate(Year = as.double(Year))
  if (is.null(labeling.year)) labeling.year <- c(min(obs_data$Year),obs_data$Year[obs_data$Year %% 5 == 0],max(obs_data$Year))
  combined_data = combined_data %>%
    mutate(label=if_else(is.na(Year),as.numeric(NA),if_else(Year %in% labeling.year, Year, as.numeric(NA)))) %>%
    mutate(SSB = SSB/xscale, R = R/yscale)
  g1 = ggplot(combined_data, aes(x=SSB,y=R,label=label)) +
    geom_path(data=dplyr::filter(combined_data, Category=="Pred"),aes(group=Regime,colour=Regime,linetype=Regime),size=2, show.legend = show.legend)+
    geom_point(data=dplyr::filter(combined_data, Category=="Obs"),aes(group=Regime,colour=Regime),size=3, show.legend = show.legend)+
    geom_path(data=dplyr::filter(combined_data, Category=="Obs"),colour="darkgray",size=1)+
    xlab(xlabel)+ylab(ylabel)+
    ggrepel::geom_label_repel()+
    theme_bw(base_size=base_size)+
    coord_cartesian(ylim=c(0,combined_data$R*1.05),expand=0)
  if (show.legend) {
    if (is.null(regime.name)) {
      regime.name = unique(combined_data$Regime)
    }
    g1 = g1 + scale_colour_hue(name=legend.title, labels = regime.name) +
      scale_linetype_discrete(name=legend.title, labels = regime.name)
  }
  if (add.info) {
    if (is.null(SRregime_result$input$regime.year)) {
      g1 = g1 +
        # labs(caption=str_c(SRregime_result$input$SR,"(",SRregime_result$input$method,
        #                    "), regime_year: ", paste0(SRregime_result$input$regime.year,collapse="&"),
        #                    ", regime_key: ",paste0(SRregime_result$input$regime.key,collapse="->"),", AICc: ",round(SRregime_result$AICc,2)))
        labs(caption=str_c(SRregime_result$input$SR,"(",SRregime_result$input$method,
                           "), No Regime", ", AICc: ",round(SRregime_result$AICc,2))
        )

    }  else {
      g1 = g1 +
        # labs(caption=str_c(SRregime_result$input$SR,"(",SRregime_result$input$method,
        #                    "), regime_year: ", paste0(SRregime_result$input$regime.year,collapse="&"),
        #                    ", regime_key: ",paste0(SRregime_result$input$regime.key,collapse="->"),", AICc: ",round(SRregime_result$AICc,2)))
        labs(caption=str_c(SRregime_result$input$SR,"(",SRregime_result$input$method,
                           "), ", "regime_par: ", paste0(SRregime_result$input$regime.par,collapse="&"),", ",
                           paste0(SRregime_result$input$regime.year,collapse="&"),
                           ", ",paste0(SRregime_result$input$regime.key,collapse="->"),
                           ", AICc: ",round(SRregime_result$AICc,2))
        )

    }
  }
  g1
}

#' 複数のVPAの結果を重ね書きする
#'
#' @param vpalist vpaの返り値をリストにしたもの; 単独でも可
#' @param vpatibble tibble形式のVPA結果も可。この場合、convert_vpa_tibble関数の出力に準じる。複数のVPA結果がrbindされている場合は、列名"id"で区別する。
#' @param what.plot 何の値をプロットするか. NULLの場合、全て（SSB, biomass, U, catch, Recruitment, fish_number, fishing_mortality, weight, maturity, catch_number）をプロットする。what.plot=c("SSB","Recruitment")とすると一部のみプロット。ここで指定された順番にプロットされる。
#' @param legend.position 凡例の位置。"top" (上部), "bottom" (下部), "left" (左), "right" (右), "none" (なし)。
#' @param vpaname 凡例につけるVPAのケースの名前。vpalistと同じ長さにしないとエラーとなる
#' @param ncol 図の列数
#'
#' @examples
#' \dontrun{
#' data(res_vpa)
#' res_vpa2 <- res_vpa
#' res_vpa2$naa <- res_vpa2$naa*1.2
#'
#' plot_vpa(list(res_vpa, res_vpa2), vpaname=c("True","Dummy"))
#' plot_vpa(list(res_vpa, res_vpa2), vpaname=c("True","Dummy"),
#'                  what.plot=c("SSB","fish_number"))
#'
#' }
#'
#' @encoding UTF-8
#'
#' @export
#'

plot_vpa <- function(vpalist, vpatibble=NULL,
                     what.plot=NULL, legend.position="top",
                     vpaname=NULL, ncol=2){

  if(!is.null(vpaname)){
    if(length(vpaname)!=length(vpalist)) stop("Length of vpalist and vpaname is different")
    names(vpalist) <- vpaname
  }

  if(is.null(vpatibble)){
    if(isTRUE("naa" %in% names(vpalist))) vpalist <- list(vpalist)
    vpadata <- vpalist %>% purrr::map_dfr(convert_vpa_tibble ,.id="id") %>%
      mutate(age=factor(age))
  }
  else{
    vpadata <- vpatibble %>%
      mutate(age=factor(age))
    if("id" %in% !names(vpadata)) vpadata$id <- "vpa1"
  }
  if(!is.null(what.plot)) vpadata <- vpadata %>%  dplyr::filter(stat%in%what.plot)

  biomass_factor <- vpadata %>% dplyr::filter(is.na(age)) %>%
    select(stat) %>% unique() %>% unlist()
  age_factor <- vpadata %>% dplyr::filter(!is.na(age)) %>%
    select(stat) %>% unique() %>% unlist()

  if(!is.null(what.plot)){
    vpadata <- vpadata %>%
      mutate(stat=factor(stat,levels=what.plot))
  }
  else{
    vpadata <- vpadata %>%
      mutate(stat=factor(stat,levels=c(biomass_factor, age_factor)))
  }

  g1 <- vpadata %>% ggplot()
  if(all(is.na(vpadata$age))){
    g1 <- g1+ geom_line(aes(x=year, y=value,lty=id))
  }
  else{
    g1 <- g1+ geom_line(aes(x=year, y=value,color=age,lty=id))
  }

  g1 <- g1 +
    facet_wrap(~stat, scale="free_y", ncol=ncol) + ylim(0,NA) +
    theme_SH(legend.position=legend.position) +
    ylab("Year") + xlab("Value")

  g1
}


#' F一定の場合で平衡状態になったときの統計量をx軸、y軸にプロットして比較する
#'
#'
#' 例えば、横軸を平均親魚量(ssb.mean)、縦軸を平均漁獲量(catch.mean)にすると漁獲量曲線が得られる。どの統計量がプロットできるかはest.MSYの返り値res_MSYの$trace以下の名前を参照(names(res_MSY$trace))。
#'
#' @param MSYlist est.MSYの返り値をリストにしたもの; 単独でも可
#' @param MSYname 凡例につけるMSYのケースの名前。MSYlistと同じ長さにしないとエラーとなる
#' @param x_axis_name x軸になにをとるか？("ssb.mean": 親魚の平均資源量, "fmulti": current Fに対する乗数、など)
#' @param y_axis_name y軸になにをとるか？("ssb.mean": 親魚の平均資源量, "catch.mean": 平均漁獲量、"rec.mean": 加入量の平均値など） get.statの返り値として出される値（またはMSYの推定結果のtrace内の表）に対応
#' @param plot_CI80 TRUE or FALSE, 平衡状態における信頼区間も追記する(現状では、縦軸が親魚量・漁獲量・加入尾数のときのみ対応)
#'
#' @examples
#' \dontrun{
#' data(res_MSY_HSL1)
#' data(res_MSY_HSL2)
#' MSY_list <- tibble::lst(res_MSY_HSL1, res_MSY_HSL2)
#' # 縦軸を漁獲量、横軸をFの大きさ
#' g1 <- compare_eq_stat(MSY_list,x_axis_name="fmulti",y_axis_name="catch.mean")
#' # 縦軸を親魚量にする
#' g2 <- compare_eq_stat(MSY_list,x_axis_name="fmulti",y_axis_name="ssb.mean")
#' # 縦軸を加入量
#' g3 <- compare_eq_stat(MSY_list,x_axis_name="fmulti",y_axis_name="rec.mean")
#' gridExtra::grid.arrange(g1,g2,g3,ncol=1)
#'
#' g3.withCI <- compare_eq_stat(MSY_list,x_axis_name="fmulti",y_axis_name="rec.mean",plot_CI80=TRUE)
#'
#' }
#'
#' @encoding UTF-8
#'
#' @export
#'

compare_eq_stat <- function(MSYlist,
                            x_axis_name="fmulti",
                            y_axis_name="catch.mean",
                            legend.position="top",
                            is_MSY_line=TRUE,
                            is.scale=FALSE,
                            MSYname=NULL,
                            plot_CI80=FALSE
){

  if(!is.null(MSYname)){
    if(length(MSYname)!=length(MSYlist)) stop("Length of MSYlist and MSYname is different")
    names(MSYlist) <- MSYname
  }
  if(isTRUE("summary" %in% names(MSYlist))) MSYlist <- list(MSYlist)

  data_yield <- purrr::map_dfr(MSYlist, function(x){
    x$trace %>% mutate(catch.order= rank(-catch.mean),
                       catch.max  = max(catch.mean)  ,
                       ssb.max    = max(ssb.mean))
  }
  ,.id="id")

  if(isTRUE(is.scale)) data_yield <- data_yield %>% mutate(catch.mean=catch.mean/catch.max,
                                                           ssb.mean=ssb.mean/ssb.max)

  g1 <- data_yield %>% ggplot()+
    geom_line(aes(x=get(x_axis_name), y=get(y_axis_name[1]), color=id))+
    theme_SH(legend.position=legend.position)+
    xlab(x_axis_name)+ylab(str_c(y_axis_name))+
    geom_vline(data=dplyr::filter(data_yield,catch.order==1),
               aes(xintercept=get(x_axis_name),color=id),lty=2)

  if(isTRUE(plot_CI80)){
    y_axis_name_L10 <- dplyr::case_when(
      y_axis_name == "catch.mean" ~ "catch.L10",
      y_axis_name == "ssb.mean"   ~ "ssb.L10",
      y_axis_name == "rec.mean"   ~ "rec.L10")
    y_axis_name_H10 <- dplyr::case_when(
      y_axis_name == "catch.mean" ~ "catch.H10",
      y_axis_name == "ssb.mean"   ~ "ssb.H10",
      y_axis_name == "rec.mean"   ~ "rec.H10")
    g1 <- g1 +
      geom_line(aes(x=get(x_axis_name), y=get(y_axis_name_L10), color=id),lty=2)+
      geom_line(aes(x=get(x_axis_name), y=get(y_axis_name_H10), color=id),lty=3)
  }

  return(g1)
}


#' 複数の管理基準値の推定結果を重ね書きする
#'
#' @param MSYlist est.MSYの返り値をリストにしたもの; 単独でも可
#' @param MSYname 凡例につけるMSYのケースの名前。MSYlistと同じ長さにしないとエラーとなる
#' @param legend.position 凡例の位置
#' @param yaxis
#'
#' @examples
#' \dontrun{
#' data(res_MSY)
#' MSY_list <- tibble::lst(res_MSY_HSL1, res_MSY_HSL2)
#' g1 <- compare_MSY(list(res_MSY, res_MSY))
#' }
#'
#' @encoding UTF-8
#'
#' @export
#'

compare_MSY <- function(MSYlist,
                        legend.position="top",
                        MSYname=NULL,
                        yaxis="Fref2Fcurrent"){

  if(!is.null(MSYname)){
    if(length(MSYname)!=length(MSYlist)) stop("Length of MSYlist and MSYname is different")
    names(MSYlist) <- MSYname
  }

  if(isTRUE("summary" %in% names(MSYlist))) MSYlist <- list(MSYlist)

  data_summary <- purrr::map_dfr(MSYlist, function(x) x$summary, .id="id")   %>%
    dplyr::filter(!is.na(RP.definition)) %>%
    mutate(label=stringr::str_c(id, RP.definition, sep="-")) %>%
    mutate(perSPR_rev=1-perSPR)

  g1 <- data_summary %>% ggplot()+
    geom_point(aes(x=SSB, y=get(yaxis), color=id))+
    ggrepel::geom_label_repel(aes(x=SSB, y=get(yaxis), color=id, label=label))+
    theme_SH(legend.position=legend.position)

  return(g1)
}

#' 複数の再生産関係を比較する関数
#'
#' @param SRlist 再生産関係の推定結果のリスト。
#' @param biomass.unit 資源量の単位
#' @param number.unit 尾数の単位
#'
#' @examples 
#' \dontrun{
#' data(res_sr_HSL1)
#' data(res_sr_HSL2)
#' 
#' (g1 <- compare_SRfit(list(HSL1=res_sr_HSL1, HSL2=res_sr_HSL2),
#'                      biomass.unit=1000, number.unit=1000))
#' 
#' }
#'
#' @export
#'
#' 

compare_SRfit <- function(SRlist, biomass.unit=1000, number.unit=1000){
    SRdata <- SRlist[[1]]$input$SRdata %>%
        as_tibble() %>%
        mutate(SSB=SSB/biomass.unit, R=R/number.unit)
    g1 <- plot_SRdata(SRdata,type="gg")

    SRpred <- purrr::map_dfr(SRlist,
                             function(x) x$pred, .id="SR_type")
    g1 <- g1+geom_line(data=SRpred,mapping=aes(x=SSB/biomass.unit,y=R/number.unit,col=SR_type)) +
        theme(legend.position="top") +
        xlab(str_c("SSB (x",biomass.unit,")")) +
        ylab(str_c("Number (x",number.unit,")")) 

  g1
}

#'
#' 将来予測の結果のリストを入れると、代表的なパフォーマンス指標をピックアップする
#'
#' @param future_list future_vpaまたはfuture.vpaの返り値のリスト
#' @param res_vpa vpaの返り値
#' @param ABC_year 特にABCに注目したい年
#' @param is_MSE MSEの結果を使うかどうか。MSEの結果の場合には、ABCや加入尾数の真の値との誤差も出力する
#' @param indicator_year ABC_yearから相対的に何年後を指標として取り出すか
#' @param Btarget 目標管理基準値の値
#' @param Blimit 限界管理基準値の値
#' @param Bban 禁漁水準の値
#' @param type 出力の形式。"long"は縦長（ggplotに渡すときに便利）、"wide"は横長（数字を直接比較するときに便利）
#' @param biomass.unit 資源量の単位
#'
#' @export
#'

get_performance <- function(future_list,res_vpa,ABC_year=2021,
                            is_MSE=FALSE,
                            indicator_year=c(0,5,10),Btarget=0, Blimit=0, Bban=0,
                            type=c("long","wide")[1],biomass.unit=10000,...){

  future_list_original <- future_list
  future_list <- purrr::map(future_list,
                            function(x) if(class(x)=="future_new")
                              format_to_old_future(x) else x)

  if(is.null(names(future_list))) names(future_list) <- 1:length(future_list)

  future_tibble <- purrr::map_dfr(1:length(future_list),
                                  function(i) convert_future_table(future_list[[i]],
                                                                   label=names(future_list)[i]) %>%
                                    rename(HCR_name=label) %>% mutate(beta=NA))

  kobe_res <- make_kobeII_table(future_tibble,res_vpa,
                                year.ssb   = ABC_year+indicator_year,
                                year.catch = ABC_year+indicator_year,
                                year.ssbtarget = ABC_year+indicator_year,
                                year.ssblimit  = ABC_year+indicator_year,
                                year.ssbban=NULL, year.ssbmin=NULL, year.ssbmax=NULL,
                                year.aav = c(ABC_year,ABC_year-1),
                                Btarget= Btarget,
                                Blimit = Blimit,
                                Bban   = Bban)

  if(isTRUE(is_MSE)){
    error_table <- purrr::map_dfr(1:length(future_list_original), function(i){
      if("SR_MSE" %in% names(future_list_original[[i]])){
        plot_bias_in_MSE(future_list_original[[i]], out="stat") %>%
          dplyr::filter(year %in% (ABC_year + indicator_year)) %>%
          group_by(year, stat) %>%
          summarise(mean_error=mean(Relative_error_normal)) %>%
          mutate(HCR_name=names(future_list)[i])
      }
      else{
        NULL
      }
    })
    error_table <- error_table %>%
      gather(key=stat_name,value=value,-HCR_name,-year,-stat) %>%
      mutate(unit="",stat_category="推定バイアス") %>%
      mutate(stat_year_name=str_c(stat_category,year)) %>%
      ungroup(year) %>%
      mutate(year=as.character(year)) %>%
      mutate(stat_name=stat) %>%
      select(-stat)
  }
  else{
    error_table <- NULL
  }

  junit <- c("","十","百","千","万")[log10(biomass.unit)+1]

  stat_data <- tibble(stat_name=c("ssb.mean","catch.mean","Pr(SSB>SSBtarget)","Pr(SSB>SSBlim)",
                                  "catch.aav"),
                      stat_category=c("平均親魚量 ", "平均漁獲量 ", "目標上回る確率 ", "限界上回る確率 ",
                                      "漁獲量変動"))

  kobe_res <- purrr::map_dfr(kobe_res[c("ssb.mean", "catch.mean", "prob.over.ssbtarget",
                                        "prob.over.ssblimit", "catch.aav")],
                             function(x) x %>% select(-beta) %>%
                               gather(key=year,value=value,-HCR_name,-stat_name)) %>%
    mutate(value=ifelse(stat_name %in% c("ssb.mean", "catch.mean"), value/biomass.unit, value)) %>%
    mutate(unit =ifelse(stat_name %in% c("ssb.mean", "catch.mean"), str_c(junit, "トン"), "%")) %>%
    mutate(unit =ifelse(stat_name %in% c("catch.aav"), "", unit)) %>%
    left_join(stat_data) %>%
    mutate(stat_year_name=str_c(stat_category,year))

  kobe_res <- bind_rows(kobe_res,error_table)

  if(type=="wide"){
    kobe_res <- kobe_res  %>%
      select(-year, -stat_name, -stat_category) %>%
      spread(key=HCR_name,value=value) %>%
      select(2:ncol(.),1)
  }

  return(tibble::lst(kobe_res,error_table))
}

#'
#' 短期的将来予測における複数の管理方策のパフォーマンスを比較する表を出力する
#'
#' @param future_list 将来予測の結果のリスト
#' @param res_vpa VPAの結果
#' @param ... get_performanceで必要な引数
#'
#'
#' @export
#'

compare_future_performance <- function(future_list,res_vpa,res_MSY,
                                       biomass.unit=1000,is_MSE=FALSE,...){
    perform_res <- get_performance(future_list=future_list, res_vpa=res_vpa,
                                   Btarget=derive_RP_value(res_MSY$summary,"Btarget0")$SSB,
                                   Blimit =derive_RP_value(res_MSY$summary,"Blimit0")$SSB,
                                   Bban   =derive_RP_value(res_MSY$summary,"Bban0")$SSB,
                                   type="long",is_MSE=is_MSE,biomass.unit=biomass.unit,...)

    g1_ssb0 <- perform_res$kobe_res %>% dplyr::filter(stat_name=="ssb.mean") %>%
        ggplot() +
    geom_bar(aes(x=HCR_name,y=value,fill=stat_category),stat="identity") +
    facet_wrap(stat_category~year,ncol=1)+coord_flip()+
    geom_label(aes(x=HCR_name,y=max(value)/2,label=str_c(round(value),unit)),
               alpha=0.5)+
    theme_SH() + theme(legend.position="top")+xlab("Senario") +
    guides(fill=guide_legend(title=""))+
    scale_fill_manual(values=c("lightblue"))

    g1_ssb <- g1_ssb0 +
        geom_hline(yintercept=derive_RP_value(res_MSY$summary,"Btarget0")$SSB/biomass.unit,
                   col="#00533E")+
        geom_hline(yintercept=derive_RP_value(res_MSY$summary,"Blimit0")$SSB/biomass.unit,
                   col="#edb918")

    g1_catch0 <- g1_ssb0 %+% dplyr::filter(perform_res$kobe_res, stat_name=="catch.mean")+
        scale_x_discrete(labels=rep("",4))+
        scale_fill_manual(values=c("lightgreen"))

    g1_catch <- g1_catch0 +
        geom_hline(yintercept=derive_RP_value(res_MSY$summary,"Btarget0")$Catch/10000,
                   col="#00533E")+
        geom_hline(yintercept=rev(colSums(res_vpa$wcaa,na.rm=T))[1]/biomass.unit,
                   col="gray",lty=2)

    g1_probtar <- g1_catch0 %+% dplyr::filter(perform_res$kobe_res, stat_name=="Pr(SSB>SSBtarget)")+
        scale_fill_manual(values=c("lightblue"))+
        geom_hline(yintercept=c(0,50,100),col="gray",lty=2)

    g1_problim <- g1_catch0 %+% dplyr::filter(perform_res$kobe_res, stat_name=="Pr(SSB>SSBlim)")+
        scale_fill_manual(values=c("gray"))+
        geom_hline(yintercept=c(0,50,100),col="gray",lty=2)

    g1_error_table <- perform_res$error_table  %>%
        ggplot() +
        geom_bar(aes(x=HCR_name,y=value,fill=stat_category),stat="identity") +
        facet_grid(year~stat_name)+coord_flip()+
        geom_label(aes(x=HCR_name,y=max(value)/2,label=str_c(round(value,2),unit)),
                   alpha=0.5)+
        theme_SH() + theme(legend.position="top")+xlab("Senario") +
        guides(fill=guide_legend(title=""))+
        scale_fill_manual(values=c("lightpink"))

    g1_performance <- gridExtra::marrangeGrob(list(g1_ssb,g1_probtar,g1_catch,g1_problim),
                                              widths=c(1.3,1,1,1),nrow=1,ncol=4)

    list(g1_performance, g1_error_table, perform_res)
    #ggsave(g1_performance, filename="g1_performance.png" ,path=output_folder,
    #           width=20, height= 10)

    #    ggsave(g1_error_table, filename="g1_error_table.png" ,path=output_folder,
    #       width=15, height= 8)

}


#'
#' @export
#'

plot_bias_in_MSE <- function(fout, out="graph", error_scale="log", yrange=NULL){

  recruit_dat  <- convert_2d_future(fout$SR_MSE[,,"recruit"], name="Recruits", label="estimate") %>%
    rename(value_est=value)
  tmp <- convert_2d_future(fout$naa[1,,],            name="Recruits", label="true")
  recruit_dat$value_true <- tmp$value

  real_ABC_dat <- convert_2d_future(fout$HCR_mat[,,"wcatch"],    name="realABC", label="estimate") %>%
    rename(value_est=value)
  tmp  <- convert_2d_future(fout$SR_MSE[,,"real_true_catch"], name="realABC", label="true")
  real_ABC_dat$value_true <- tmp$value

  pseudo_ABC_dat <- convert_2d_future(fout$HCR_mat[,,"wcatch"],    name="pseudoABC", label="estimate") %>%
    rename(value_est=value)
  tmp  <- convert_2d_future(fout$SR_MSE[,,"pseudo_true_catch"], name="pseudoABC", label="true")
  pseudo_ABC_dat$value_true <- tmp$value

  alldat <- bind_rows(recruit_dat, real_ABC_dat, pseudo_ABC_dat) %>%
    dplyr::filter(value_est>0) %>%
    mutate(Relative_error_log=(log(value_est)-log(value_true))/log(value_true),
           Relative_error_normal=((value_est)-(value_true))/(value_true),
           Year=factor(year))

  g1 <- alldat %>% ggplot() +
    geom_boxplot(aes(x=Year,
                     #                         y=Relative_error_log,
                     y={if(error_scale=="log") Relative_error_log else Relative_error_normal},
                     fill=stat)) +
    facet_wrap(~stat,scale="free_y") +
    geom_hline(yintercept=0) +
    theme_SH() +
    ylab(str_c("Relative error (",error_scale,")"))

  if(!is.null(yrange)) g1 <- g1 + coord_cartesian(ylim=yrange)

  if(out=="graph"){
    return(g1)
  }
  else{
    return(alldat)
  }

}

#'
#' calculate F/Ftarget based on F_%SPR multiplier
#'
#' @param faa F at age
#' @param waa weight at age
#' @param maa maturity at age
#' @param M natural morality at age
#' @param SPRtarget target SPR
#'
#' @export
#'


calc_Fratio <- function(faa, waa, maa, M, SPRtarget=30, waa.catch=NULL,Pope=TRUE){
  tmpfunc <- function(x,SPR0=0,...){
    SPR_tmp <- calc.rel.abund(sel=faa,Fr=exp(x),na=length(faa),M=M, waa=waa, waa.catch=waa.catch,
                              min.age=0,max.age=Inf,Pope=Pope,ssb.coef=0,maa=maa)$spr %>% sum()
    sum(((SPR_tmp/SPR0*100)-SPRtarget)^2)
  }
  if(sum(faa)==0){ return(NA) }
  else{
    tmp <- !is.na(faa)
    SPR0 <- calc.rel.abund(sel=faa,Fr=0,na=length(faa),M=M, waa=waa, waa.catch=waa.catch,maa=maa,
                           min.age=0,max.age=Inf,Pope=Pope,ssb.coef=0)$spr %>% sum()
    opt_res <- optimize(tmpfunc,interval=c(-10,10),SPR0=SPR0)
    SPR_est <- calc.rel.abund(sel=faa,Fr=exp(opt_res$minimum),na=length(faa),
                              M=M, waa=waa, waa.catch=waa.catch,maa=maa,
                              min.age=0,max.age=Inf,Pope=Pope,ssb.coef=0)$spr %>% sum()
    SPR_est <- SPR_est/SPR0 * 100
    if(abs(SPR_est-SPRtarget)>0.01) {browser(); return(NA)}
    else return(1/exp(opt_res$minimum))
  }
}

#'
#' @export
#'
#'

calc_akaike_weight <- function(AIC) exp(-AIC/2)/sum(exp(-AIC/2))

