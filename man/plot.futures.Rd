% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/future.r
\encoding{UTF-8}
\name{plot.futures}
\alias{plot.futures}
\title{複数の将来予測の結果をプロットする（ggplotは使わず）}
\usage{
\method{plot}{futures}(
  fres.list,
  conf = c(0.1, 0.5, 0.9),
  target = "SSB",
  legend.text = "",
  xlim.tmp = NULL,
  y.scale = 1,
  det.run = TRUE
)
}
\arguments{
\item{fres.list}{future.vpaからの出力結果をリストで並べたもの}
}
\description{
複数の将来予測の結果をプロットする（ggplotは使わず）
}
