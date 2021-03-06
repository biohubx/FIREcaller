# !/usr/bin/env Rscript
# 9/20/2020
#
#' @title FIREcaller: an R package for detecting frequently interacting regions from Hi-C data
#' @description This function FIREcaller is a user-friendly R package for detecting FIREs from Hi-C data.
#' FIREcaller takes raw Hi-C NxN contact matrix as input, performs within-sample and cross-sample normaliza-tion via
#' HiCNormCis and quantile normalization respectively, and outputs FIRE scores, FIREs and super-FIREs.
#' The input file needs to be ATLEAST a NxN upper-triangular matrix OR a NxN symmetric matrix
#' @usage FIREcaller(prefix.list=(...), gb=c("hg19","GRCh38","mm9","mm10"), map_file="", rm_mhc=c("TRUE","FALSE"),rm_EBL=c("TRUE","FALSE"),upper_cis=200000, dist=c('poisson','nb'), rm_perc=0.25) 
#' @param prefix.list a list of samples that correspond to the names of the gzipped files.
#' @param gb a string that defines the genome build type.If missing, an error message is returned.
#' @param map_file a string that defines the name of the mappability file specific to the samples genome build, restriction enzyme, and resolution. Only contains chromosomes you want to input. See read me for format.
#' @param rm_mhc a logicalvalue indicating whether to remove the mhc region of the sample. Default is "TRUE".
#' @param rm_EBL a logical value indicating whether to remove the ENCODE blacklist regions of the sample. Default is "TRUE".
#' @param upper_cis is a bound for the cis-interactions calculation. The default is 200Kb
#' @param dist is the distribution specification for the HiCNormCis normalization and FIREscore calculation. The default is Poisson.
#' @param rm_perc is the percentage of "bad-bins" in a cis-interaction calculation to filter. Default is 25%
#' @details The process includes calculating the raw fire scores, filtering (with the option of removing the MHC region and ENCODE black list), HiCNormCis, Quantile Normalization (if number of samples > 1), highlighting significant Fire Scores, and calculating the Super Fires.
#' @return Two sets of files will be returned. The total number of files outputted are 1+ (number of prefixes/samples):
#' @return \itemize{
#'     \item Fire: a single text file is outputted for all the samples and all chromosomes.This file contains the Fire Score, associated ln(pvalue), and an indicator if the region is a FIRE or not with I(pvalues > -ln(0.05)).
#'     \item SuperFire: a text file for each sample with a list of Super Fires and corresponding -log10(pvalue).
#'     }
#' @note Each sample must have a NxN contact frequency matrix for all autosomal chromosomes.
#' The prefix.list corresponds to the naming convention of the NxN contact frequency matrices.
#' If length(prefix.list)>1, quantile normalization is performed.
#' @seealso Paper: https://doi.org/10.1016/j.celrep.2016.10.061
#' @author Crowley, Cheynna Anne <cacrowle@live.unc.edu>, Yuchen Yang <yyuchen@email.unc.edu>,
#' Ming Hu <afhuming@gmail.com>, Yun Li <yunli@med.unc.edu>
#' @references Cheynna Crowley, Yuchen Yang, Ming Hu, Yun Li. FIREcaller: an R package for detecting frequently interacting re-gions from Hi-C data
#' @import MASS
#' @import preprocessCore
#' @import data.table
#' @importFrom stats glm
#' @importFrom stats pnorm
#' @importFrom stats sd
#' @importFrom utils write.table
#' @importFrom utils read.table
#' @examples
#' # set working directory: the location of the NxN matrices and mappability files
#' setwd('~/Desktop/FIREcaller_example')
#'
#' # define the prefix.list according to the naming convention of the NxN matrices
#' prefix.list <- c('Hippo')
#'
#' #define the genome build
#' gb<-'hg19'
#'
#' #define the name of the mappability file
#' map_file<-'F_GC_M_HindIII_40KB_hg19.txt.gz'
#'
#' #define whether to remove MHC region; default=TRUE
#' rm_mhc <- TRUE
#' 
#' #' #define whether to remove ENCODE blacklist region; default=TRUE
#' rm_EBL<- TRUE
#'
#' # define the upper bound of the cis-interactions; default=200,000; if not a multiple of the bin, then takes the ceiling;
#' upper_cis<-200000
#'
#'# define whether the distribution should be poisson or negative binomial; default=poisson
#' dist<-'poisson'
#'
#'# define the percentage to remove problematic bins (0-1)
#'rm_perc<-0.25
#'
#' #run the function
#' FIREcaller(prefix.list,gb, map_file, rm_mhc, rm_EBL, upper_cis, dist,rm_perc)
#' @export


FIREcaller <- function(prefix.list, gb, map_file, rm_mhc = TRUE,rm_EBL=TRUE, upper_cis=200000, dist='poisson',rm_perc=0.25){

  options(scipen = 999)
  ref_file <-as.data.frame(fread(map_file))
  colnames(ref_file) <- c("chr", "start", "end", "F", "GC", "M","EBL")
  res <- as.numeric(ref_file[1,3]-ref_file[1,2])
  #res <- resolution(ref_file)
  #binsize <- bs(ref_file)
  #chr_list <- chromosome_list(gb,chrX)
  chr_list<-unique(ref_file$chr)
  bin_num <- ceiling(upper_cis/res)

  if(is.null(map_file) == 'TRUE'){stop('Please enter a mappability file')}
  if(length(ref_file) != 7){stop('Please refer to documentation on mappability file format')}
  if(ref_file$start[1] != 0){stop('Please refer to documentation on mappability file format')}
  #if(is.null(rm_mhc) == 'TRUE'|| rm_mhc=='TRUE'){rm_mhc<-'TRUE'}
  #if(rm_mhc == 'FALSE'){rm_mhc<-'FALSE'}
  #if(!rm_mhc %in% c('TRUE','FALSE')){stop('Format for remove mhc is incorrect. Please refer to documentation')}
  #if(is.null(chr_list) == 'TRUE'){stop('Format for genome build is incorrect. Please refer to documentation')}

  t <- cis_15KB_200KB(prefix.list, chr_list, bin_num, ref_file)
  t2 <- filter_count(file = t, rm_mhc, bin_num, gb, res,rm_perc,rm_EBL)
  if(dist=='poisson'){t3 <- HiCNormCis(file = t2)} else if (dist=='nb'){t3<-HiCNormCis.2(file=t2)}
  if(length(prefix.list) > 1){t4 <- quantile_norm(file = t3)}else{t4 <- t3}
  final_fire <- Fire_Call(file = t4, prefix.list)
  write.table(final_fire, paste0('FIRE_ANALYSIS_', res,"_",upper_cis,'_',dist,'.txt'), quote = FALSE, row.names = FALSE)
  Super_Fire(final_fire, prefix.list)
}

#resolution <- function(ref_file){
#  res <- NULL
#  map <- ref_file
#  res <- (map$end[1] - map$start[1])
#  return(res)
#}

#isSym<-function(m){
#  file<-sample
#  diag(m) <- 0
#  if(isSymmetric(m)==TRUE){
#    m[lower.tri(m)] <- 0
#print(paste0('Reading in, ',file,', symmetric matrix'))
#    return(m)
#  } else if(isSymmetric(m)==FALSE | m[lower.tri(m)]!= 0){
#    stop('Input Matrix is not symmetric or upper-triangular')
#  }
#}

#bs <- function(ref_file){
#  binsize <- NULL
#  map <- ref_file
#  ind <- (map$end[1] - map$start[1])/1000
#  binsize <- paste0(ind, "KB")
#  return(binsize)
#}

#chromosome_list <- function(gb,chrX){
#  chr_list <- NULL
#  if(toupper(gb) == 'HG19' && toupper(chrX)==FALSE){chr_list <- paste0('chr', 1:22)}
#  if(toupper(gb) == 'HG19' && toupper(chrX)==TRUE){chr_list <- c(paste0('chr', 1:22),'chrX')}#
#  if(toupper(gb) == 'GRCH38' && toupper(chrX)==FALSE){chr_list <- paste0('chr', 1:22)}
#  if(toupper(gb) == 'GRCH38' && toupper(chrX)==TRUE){chr_list <- c(paste0('chr', 1:22),'chrX')}
#
#  if(toupper(gb) == 'MM9' && toupper(chrX)==FALSE){chr_list <- paste0('chr', 1:19)}
#  if(toupper(gb) == 'MM10' && toupper(chrX)==FALSE){chr_list <- paste0('chr', 1:19)}
#  return(chr_list)
#}

cis_15KB_200KB <- function(prefix.list, chr_list, bin_num, ref_file){
  all <- NULL
  for(j in 1:length(chr_list)){
    chr <- chr_list[j]
    x <- cis_single_chr(prefix.list, chr, bin_num, ref_file)
    all <- rbind(all,x)
  }
  return(all)
}


cis_single_chr <- function(prefix.list, chr, bin_num, ref_file){
  file_list <- paste0(prefix.list, '_', chr, '.gz')
  ref_file_chr <- ref_file[ref_file$chr == chr,]
  all_samples <- as.data.frame(ref_file_chr)

  for(i in 1:length(file_list)){
    matrix <- as.matrix(fread(file_list[i], data.table = FALSE))
    #nrow(matrix)
    colnames(matrix)<-rownames(matrix)
    #matrix2<-isSym(matrix)
    sample <- prefix.list[i]
    diag(matrix) <- 0
    x <- calculate_cis(matrix, chr, bin_num, sample, ref_file_chr)
    all_samples <- merge(all_samples, x, by = c("chr", "start", "end", "F", "GC", "M","EBL"), sort = FALSE, all = TRUE)
  }

  return(all_samples)
}


calculate_cis <- function(matrix, chr, bin_num, sample, ref_file_chr){
  length <- nrow(matrix)
  x <- vector("integer", length = length)

  for(i in 1:length){
    x[i] <- ifelse(i <= bin_num,
                   sum(matrix[i,(i:(i+bin_num))], matrix[(1:i),i]),
                   ifelse((i+bin_num) > length,
                          sum(matrix[i,(i:length)], matrix[(i-bin_num):i,i]), #case 2
                          sum(matrix[((i-bin_num)):i, i], matrix[i,(i:(i+bin_num))]))) #case 3
  }
  x <- as.data.frame(x)
  colnames(x) <- sample
  final <- cbind(ref_file_chr, x)
  return(final)
}

filter_count <- function(file, rm_mhc, bin_num, gb, res,rm_perc,rm_EBL){
  options(scipen = 999)

  y <- file
  # filter 1: find bad bins-- F=0, GC=0 or M=0
  y$flag <- 0
  y$flag <- ifelse(y$F == 0 | y$GC == 0 | y$M == 0, 1, 0)

  # filter 2: find neighbor bins
  y2 <- y
  y2$bad_neig <- 0
  for(i in 1:nrow(y2)){
    if((i >= bin_num) & (i + bin_num <= nrow(y2))){
      y2$bad_neig[i] <- sum(y2[c(((i - bin_num):i),(i:(i + bin_num))),"flag"])
    }
    if(i < bin_num){
      y2$bad_neig[i] <- sum(y2[c((1:i),(i:(i + bin_num))),"flag"])
    }
    if((i + bin_num) > nrow(y2)){
      y2$bad_neig[i]<-sum(y2[c(((i - bin_num):i),(i:nrow(y2))),"flag"])
    }
  }

  #find percentage of bad bins of
  y2$perc <- y2$bad_neig/(2 * bin_num)

  #remove the bad bins and if 25 percent of the neighbooring bins are "bad"
  y3 <- y2[y2$flag == 0,]
  y4 <- y3[y3$perc <= rm_perc,]

  # filter 3: remove if Mapp<0.9
  y5 <- y4[y4$M > 0.9,]

  #remove the last two columns
  n1 <- ncol(y5)
  n2 <- n1-2
  y6 <- y5[,-c(n2:n1)]

  #filter 4: MHC regions
  if(rm_mhc == TRUE){
    y7 <- remove_mhc(y6, gb, res)
  } else{
    y7 <- y6
  }
  
  if(rm_EBL == TRUE){
    y8 <-y7[y7$EBL==0,]
  } else{
    y8<-y7
  }
  
  
  return(y8)
}

remove_mhc <- function(y, gb, res){
  if(toupper(gb) == 'HG19'){y2 <- mhc_hg19(y, res)}
  if(toupper(gb) == 'GRCH38'){y2 <- mhc_grch38(y, res)}
  if(toupper(gb) == 'MM9'){y2 <- mhc_mm9(y, res)}
  if(toupper(gb) == 'MM10'){y2 <- mhc_mm10(y, res)}
  return(y2)
}

mhc_hg19 <- function(y, res) {
  y_remove <- (y$chr == "chr6" & y$start > floor(28477797/res)*res & y$end <= ceiling(33448354/res)*res)
  y <- y[!y_remove,]
  return(y)
}

mhc_grch38 <- function(y, res) {
  y_remove <- (y$chr == "chr6" & y$start > floor(28510120/res)*res & y$end <= ceiling(33480577/res)*res)
  y <- y[!y_remove,]
  return(y)
}

mhc_mm9 <- function(y, res) {
  y_remove <- (y$chr == "chr17" & y$start > floor(33888191/res)*res & y$end <= ceiling(35744546/res)*res)
  y_remove2 <- (y$chr == "chr17" & y$start > floor(36230820/res)*res & y$end <= ceiling(38050373/res)*res)
  y <- y[!y_remove,]
  y <- y[!y_remove2,]
  return(y)
}

mhc_mm10 <- function(y,res) {
  y_remove <- (y$chr == "chr17" & y$start > floor(33681276/res)*res & y$end <= ceiling(38548659/res)*res)
  y <- y[!y_remove,]
  return(y)
}



#neg_bin<-function(x,id){
#  fit<-glm.nb(x[,id] ~ x$F + x$GC + x$M)
#  return(fit)
#}

HiCNormCis <- function(file){
  x <- file[,-7]
  corout <- matrix(0, nrow = ncol(x)-6, ncol = 6)
  FIREscore <- x[,1:3]
  for(id in 7:(ncol(x))){
    y <- x[,id]
    fit <- glm(x[,id] ~ x$F + x$GC + x$M, family="poisson")
    #summary(fit)
    coeff <- round(fit$coeff, 8)
    res <- round(x[,id]/exp(coeff[1] + coeff[2]*x$F + coeff[3]*x$GC + coeff[4]*x$M), 4)
    FIREscore <- cbind(FIREscore, res)
  }

  FIREscore <- as.data.frame(FIREscore)
  return(FIREscore)
}

HiCNormCis.2 <- function(file){
  x <- file[,-7]
  corout <- matrix(0, nrow = ncol(x)-6, ncol = 6)
  FIREscore <- x[,1:3]
    for(id in 7:(ncol(x))){
      y <- x[,id]
      fit<-glm.nb(x[,id] ~ x$F + x$GC + x$M)
      #summary(fit)
      coeff <- round(fit$coeff, 8)
      res <- round(x[,id]/exp(coeff[1] + coeff[2]*x$F + coeff[3]*x$GC + coeff[4]*x$M), 4)
      FIREscore <- cbind(FIREscore, res)
    }

  FIREscore <- as.data.frame(FIREscore)
  return(FIREscore)
}

quantile_norm <- function(file){
  x <- file
  y <- x[, 4:ncol(x)]
  yqq <- normalize.quantiles(as.matrix(y))
  z <- cbind(x[,1:3], round(yqq,4))
  z <- as.data.frame(z)
  colnames(z) <- colnames(x)
  return(z)
}

Fire_Call <- function(file, prefix.list){
  x<- file
  annp <- x[, 1:3] #fire scores
  annf <- x[, 1:3]
  alpha<-0.05
  for(id in 4:ncol(x)){
    y <- x[, id]
    mean(y)
    ym  <- mean(y)
    ysd <- sd(y)
    p <- round(-pnorm(y,  mean = ym, sd = ysd, lower.tail = FALSE, log.p = TRUE), 4) #returns log pvalue
    q <- x[ p > -log(alpha),]
    f <- as.numeric(I(p > -log(alpha)))
    annp <- cbind(annp, p)
    annf <- cbind(annf, f)
  }

  annp <- as.data.frame(annp) # log(p-values) scores
  annf <- as.data.frame(annf) #indicators for pvalues > -log(0.05)
  fires <- x

  colnames(annp) <- c('chr', 'start', 'end', paste0(prefix.list, '_neg_ln_pval'))
  colnames(annf) <- c('chr', 'start', 'end', paste0(prefix.list, '_indicator'))
  colnames(fires) <- c('chr', 'start', 'end', paste0(prefix.list, '_norm_cis'))

  final0 <- merge(fires, annp, by = c('chr', 'start', 'end'), all=TRUE, sort = FALSE)
  final <- merge(final0, annf, by = c('chr', 'start', 'end'), all = TRUE, sort = FALSE)
  return(final)
}


Super_Fire <- function(final_fire, prefix.list){
  final_fire<-as.data.frame(final_fire)
  length_pl <- as.numeric(length(prefix.list))
  NP <- final_fire[, c(1:3,(3+1+length_pl):(3+2*length_pl))]
  colnames(NP) <- c('chr', 'start', 'end', prefix.list)
  ID <- final_fire[, c(1:3,(1+3+2*length_pl):ncol(final_fire))]
  colnames(ID) <- c('chr', 'start', 'end', prefix.list)
  
  
  for(INDEX in 4:(length_pl+3)){
    x0 <- ID[, c(1:3, INDEX) ]
    y0 <- NP[, c(1:3, INDEX) ]
    
    x <- x0[x0[,4]==1,]
    z <- y0[x0[,4]==1,]
    
    final <- NULL
    chr.list<-unique(x0$chr)
    for(chrid in 1:length(chr.list)){
      u <- z[ z[,1] == chr.list[chrid],]
      u2<-as.data.frame(u[1,])
      if(nrow(u)>2){
        out <- NULL
        
        for(i in 2: (nrow(u)) ){
          t<-nrow(u2)
          start <- as.numeric(u2[t, 2])
          end <- as.numeric(u2[t, 3])
          sum <-as.numeric(u2[t,4])
          if(abs(end-as.numeric(as.numeric(u[i, 2])))==0){
            u2[t,1]<-chr.list[chrid]
            u2[t,2]<-start
            u2[t,3]<-as.numeric(as.numeric(u[i, 3]))
            u2[t,4]<-sum+as.numeric(as.numeric(u[i, 4]))
          }
          if(abs(end-as.numeric(as.numeric(u[i, 2])))>0){
            u2[t+1,1]<-chr.list[chrid]
            u2[t+1,2]<-as.numeric(u[i, 2])
            u2[t+1,3]<-as.numeric(u[i, 3])
            u2[t+1,4]<-as.numeric(u[i, 4])
          }
        }
        
        colnames(u2)<-c('chr', 'start', 'end', 'cum_FIRE_score')
        
        final <- rbind(final, u2)
      }
    }
    x <- final
    
    #max(final$cum_FIRE_score)
    y <- x[order(x$cum_FIRE_score),]
    rank<-seq(1,nrow(y),1)
    z <- cbind(rank, y)
    #scale data to 0,1
    z[,6] <- z[,1]/max(z[,1]) #divide each rank by the max
    z[,7] <- z[,5]/max(z[,5]) #divide each score by the max
    
    z[,8] <-  1/sqrt(2)*z[,6] + 1/sqrt(2)*z[,7]
    z[,9] <- -1/sqrt(2)*z[,6] + 1/sqrt(2)*z[,7]
    
    RefPoint <- z[z[,9] == min(z[, 9]), 1] # 1423
    RefValue <- z[RefPoint, 5]
    
    xout <- z[z[,5] >= RefValue,c(2:5)]
    #xout$NegLog10Pvalue <- round(xout$cum_FIRE_score/log(10), 4)
    
    write.table(xout, file = paste('super_FIRE_call_', colnames(ID)[INDEX], '.txt', sep=''), row.names = F, col.names = T, sep = '\t', quote = F)
  }
}
