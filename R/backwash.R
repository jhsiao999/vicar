## Functions for performing BACKWASH.

#' BACKWASH: Bayesian Adjustment for Confounding Knitted With Adaptive
#' SHrinkage.
#'
#' This function implements the full BACKWASH method. This method is
#' very similar to the \code{\link{mouthwash}} method with one very
#' key difference: rather than estimate the confounders by maximum
#' likelihood, backwash goes more Bayesian and places a g-like prior
#' on the confounders. We fit the model by variational approximations.
#'
#' The assumed model is \deqn{Y = X\beta + Z\alpha + E.} \eqn{Y} is a
#' \eqn{n} by \code{p} matrix of response variables. For example, each
#' row might be an array of log-transformed gene-expression data.
#' \eqn{X} is a \eqn{n} by \eqn{q} matrix of observed covariates. It
#' is assumed that all but one column of which contains nuisance
#' parameters. For example, the first column might be a vector of ones
#' to include an intercept. \eqn{\beta} is a \eqn{q} by \eqn{p} matrix
#' of corresponding coefficients.  \eqn{Z} is a \eqn{n} by \eqn{k}
#' matrix of confounder variables. \eqn{\alpha} is the corresponding
#' \eqn{k} by \eqn{p} matrix of coefficients for the unobserved
#' confounders. \eqn{E} is a \eqn{n} by \eqn{p} matrix of error
#' terms. \eqn{E} is assumed to be matrix normal with identity row
#' covariance and diagonal column covariance \eqn{\Sigma}. That is,
#' the columns are heteroscedastic while the rows are homoscedastic
#' independent.
#'
#' This function will first rotate \eqn{Y} and \eqn{X} using the QR
#' decomposition. This separates the model into three parts. The first
#' part contains nuisance parameters, the second part contains the
#' coefficients of interest, and the third part contains the
#' confounders. \code{backwash} applies a user-provided factor
#' analysis to the third part to estimate the confounding factors,
#' then places a g-like prior on the confounders corresponding to the
#' second equation.  It then jointly estimates the coefficients of
#' interest and the posterior of the confounders using a VEM
#' (Variational Expectation Maximization) algorithm, placing a
#' g-prior on the hidden confounders.
#'
#' There are a couple forms of factor analysis available in this
#' package. The default is PCA with the column-wise residual
#' mean-squares as the estimates of the column-wise variances.
#'
#' For instructions and examples on how to specify your own factor analysis, run the following code in R:
#' \code{utils::vignette("customFA", package = "vicar")}. If it doesn't work, then you probably haven't built
#' the vignettes. To do so, see \url{https://github.com/dcgerard/vicar#vignettes}.
#'
#'
#' @author David Gerard
#'
#' @inheritParams vruv4
#' @inheritParams mouthwash
#'
#' @return \code{backwash} returns a list with some or all of the
#'     following elements:
#'
#'     \code{result}: A data frame with the following columns:
#'     \itemize{
#'         \item{\code{betahat}:}{ The ordinary least squares (OLS) coefficients for the variable of interest.}
#'         \item{\code{sebetahat}:}{ The standard errors of the OLS regression coefficients (with or without limma-shrinkage depending on the argument of \code{limmashrink}).}
#'         \item{\code{NegativeProb}:}{ The posterior probability of an effect being less than zero.}
#'         \item{\code{PositiveProb}:}{ The posterior probability of an effect being greater than zero.}
#'         \item{\code{lfsr}:}{ The local false sign rate for the effects. See Stephens (2016).}
#'         \item{\code{svalue}:}{ The estimated average error rate in sign detection.}
#'         \item{\code{lfdr}:}{ The local false discovery rates.}
#'         \item{\code{qvalue}:}{ The estimated average error rate in signal detection.}
#'         \item{\code{PosteriorMean}:}{ The posterior means of the effects.}
#'         \item{\code{PosteriorSD}:}{ The posterior standard deviations of the effects.}
#'     }
#'
#'     \code{elbo}: The value of the evidence lower bound at the final
#'     parameter values.
#'
#'     \code{xi}: The estimated variance scaling parameter.
#'
#'     \code{phi}: The estimated "g" parameter in the g-prior on the confounders.
#'
#'     \code{z2hat}: A function of the confounders. Mostly used for
#'     debugging.
#'
#'     \code{pi0}: The estimated proportion of null effects.
#'
#'     \code{Zhat}: The estimate of the confounders.
#'
#'     \code{alphahat}: The estimate of the coefficients of the
#'     confounders.
#'
#'     \code{sig_diag}: The estimate of the variances.
#'
#'     \code{fitted_g}: A list with the following elements:
#'     \itemize{
#'         \item{\code{pivec}:}{ The estimated prior mixing proportions.}
#'         \item{\code{tau2_seq}:}{ The prior mixing variances.}
#'         \item{\code{means}:}{ A matrix of the variational mixing means. The columns index the observations and the rows index the mixing distributions.}
#'         \item{\code{variances}:}{ A matrix of the variational mixing variances. The columns index the observations and the rows index the mixing distributions.}
#'         \item{\code{proportions}:}{ A matrix of the variational mixing proportions. The columns index the observations and the rows index the mixing distributions.}
#'     }
#'
#' @export
#'
#' @seealso \code{\link{mouthwash}} For a similar method that maximizes over the hidden confounders
#'     rather than puts a prior on them.
#'
#' @references Matthew Stephens. False discovery rates: a new deal. Biostatistics, 2016. doi: \href{http://dx.doi.org/10.1093/biostatistics/kxw041}{10.1093/biostatistics/kxw041}
#'
#' @examples
#' library(vicar)
#'
#' ## Generate data ----------------------------------------------------------
#' set.seed(116)
#' n <- 13
#' p <- 101
#' k <- 2
#' q <- 3
#' is_null       <- rep(FALSE, length = p)
#' is_null[1:57] <- TRUE
#'
#' X <- matrix(stats::rnorm(n * q), nrow = n)
#' B <- matrix(stats::rnorm(q * p), nrow = q)
#' B[2, is_null] <- 0
#' Z <- X %*% matrix(stats::rnorm(q * k), nrow = q) +
#'      matrix(rnorm(n * k), nrow = n)
#' A <- matrix(stats::rnorm(k * p), nrow = k)
#' E <- matrix(stats::rnorm(n * p, sd = 1 / 2), nrow = n)
#' Y <- X %*% B + Z %*% A + E
#'
#' ## Fit BACKWASH -----------------------------------------------------------
#' bout <- backwash(Y = Y, X = X, k = k, include_intercept = FALSE,
#'                  cov_of_interest = 2)
#' bout$pi0 ## Estimate
#' mean(is_null) ## Truth
#'
#' ## Fit MOUTHWASH ----------------------------------------------------------
#' mout <- mouthwash(Y = Y, X = X, k = k, include_intercept = FALSE,
#'                   cov_of_interest = 2)
#' mout$pi0 ## Estimate
#' mean(is_null) ## Truth
#'
#' ## Very Similar LFDR's ----------------------------------------------------
#' graphics::plot(mout$result$lfdr, bout$result$lfdr, col = is_null + 3,
#'                xlab = "MOUTHWASH", ylab = "BACKWASH", main = "LFDR's")
#' graphics::abline(0, 1, lty = 2)
#' graphics::legend("bottomright", legend = c("Null", "Non-null"), col = c(4, 3),
#'                  pch = 1)
#'
#' ## Exact Same ROC Curves --------------------------------------------------
#' morder_lfdr <- order(mout$result$lfdr)
#' mfpr <- cumsum(is_null[morder_lfdr]) / sum(is_null)
#' mtpr <- cumsum(!is_null[morder_lfdr]) / sum(!is_null)
#'
#' border_lfdr <- order(bout$result$lfdr)
#' bfpr <- cumsum(is_null[border_lfdr]) / sum(is_null)
#' btpr <- cumsum(!is_null[border_lfdr]) / sum(!is_null)
#'
#' graphics::plot(bfpr, btpr, type = "l", xlab = "False Positive Rate",
#'                ylab = "True Positive Rate", main = "ROC Curve", col = 3,
#'                lty = 2)
#' graphics::lines(mfpr, mtpr, col = 4, lty = 1)
#' graphics::abline(0, 1, lty = 2, col = 1)
#' graphics::legend("bottomright", legend = c("MOUTHWASH", "BACKWASH"), col = c(4, 3),
#'                  lty = c(1, 2))
#'
#' ## But slightly different ordering ----------------------------------------
#' graphics::plot(morder_lfdr, border_lfdr, col = is_null + 3, xlab = "MOUTHWASH",
#'                ylab = "BACKWASH", main = "Order")
#' graphics::legend("bottomright", legend = c("Null", "Non-null"), col = c(4, 3),
#'                  pch = 1)
#'
backwash <- function(Y, X, k = NULL, cov_of_interest = ncol(X),
                     include_intercept = TRUE, limmashrink = TRUE,
                     fa_func = pca_naive, fa_args = list(),
                     lambda_type = c("zero_conc", "uniform"),
                     pi_init_type = c("zero_conc", "uniform", "random"),
                     grid_seq = NULL, lambda_seq = NULL,
                     lambda0 = 10, scale_var = TRUE,
                     sprop = 0, var_inflate_pen = 0) {

    ## Check input -----------------------------------------------------------
    assertthat::assert_that(is.matrix(Y))
    assertthat::assert_that(is.matrix(X))
    assertthat::are_equal(nrow(Y), nrow(X))
    assertthat::assert_that(is.numeric(cov_of_interest))
    assertthat::assert_that(is.logical(include_intercept))
    assertthat::assert_that(is.logical(limmashrink))
    assertthat::assert_that(is.function(fa_func))
    assertthat::assert_that(is.list(fa_args))
    assertthat::assert_that(lambda0 >= 1)
    assertthat::assert_that(is.logical(scale_var))
    assertthat::assert_that(sprop >= 0)
    assertthat::assert_that(var_inflate_pen >= 0)

    if (scale_var & sprop == 1 & var_inflate_pen == 0) {
      stop("sprop cannot be 1 when scale_var is TRUE and var_inflate_pen = 0.")
    }

    lambda_type <- match.arg(lambda_type)
    pi_init_type <- match.arg(pi_init_type)

    ## Rotate ----------------------------------------------------------------
    rotate_out <- rotate_model(Y = Y, X = X, k = k,
                               cov_of_interest = cov_of_interest,
                               include_intercept = include_intercept,
                               limmashrink = limmashrink, fa_func = fa_func,
                               fa_args = fa_args, do_factor = TRUE)

    ## rescale alpha and sig_diag by R22 to get data for second step ---------
    alpha_tilde <- rotate_out$alpha / c(rotate_out$R22)
    S_diag      <- c(rotate_out$sig_diag / c(rotate_out$R22 ^ 2))
    betahat_ols <- matrix(rotate_out$betahat_ols, ncol = 1)

    ## Exchangeable versions of the models ---------------------------------------------
    if (sprop > 0) {
      sgamma           <- S_diag ^ (-1 * sprop / 2)
      alpha_tilde_star <- alpha_tilde * sgamma
      betahat_ols_star <- betahat_ols * sgamma
      S_diag_star      <- S_diag ^ (1 - sprop)
    } else {
      alpha_tilde_star <- alpha_tilde
      betahat_ols_star <- betahat_ols
      S_diag_star      <- S_diag
    }

    ## Set grid and penalties ------------------------------------------------
    if (!is.null(lambda_seq) & is.null(grid_seq)) {
        stop("lambda_seq specified but grid_seq is NULL")
    }

    if (is.null(grid_seq)) {
        grid_vals <- get_grid_var(betahat_ols = betahat_ols_star, S_diag = S_diag_star)
        tau2_seq <- sign(grid_vals$tau2_seq) * sqrt(abs(grid_vals$tau2_seq))
    } else {
        tau2_seq <- grid_seq
    }
    M <- length(tau2_seq)
    zero_spot <- which(abs(tau2_seq) < 10 ^ -14)
    assertthat::are_equal(length(zero_spot), 1)

    if (is.null(lambda_seq)) {
        if (lambda_type == "uniform") {
            lambda_seq <- rep(1, M)
        } else if (lambda_type == "zero_conc") {
            lambda_seq <- rep(1, M)
            lambda_seq[zero_spot] <- lambda0
        }
    }

    val <- backwash_second_step(betahat_ols = betahat_ols_star,
                                S_diag = S_diag_star,
                                alpha_tilde = alpha_tilde_star,
                                tau2_seq = tau2_seq,
                                lambda_seq = lambda_seq,
                                pi_init_type = pi_init_type,
                                scale_var = scale_var, sprop = sprop,
                                var_inflate_pen = var_inflate_pen)

    Y1  <- rotate_out$Y1
    Z2 <- val$z2hat
    Z3 <- rotate_out$Z3
    if (!is.null(Y1)) {
      R12 <- rotate_out$R12
      R11 <- rotate_out$R11
      Q   <- rotate_out$Q
      beta1_ols <- solve(R11) %*% (Y1 - R12 %*% t(betahat_ols))
      resid_top <- Y1 - R12 %*% t(val$result$PosteriorMean) - R11 %*% beta1_ols
      Z1  <- solve(t(alpha_tilde) %*% diag(1 / rotate_out$sig_diag) %*% alpha_tilde) %*%
        t(alpha_tilde) %*% diag(1 / rotate_out$sig_diag) %*% t(resid_top)
      Zhat <- Q %*% rbind(t(Z1), t(Z2), Z3)
    } else {
      Q   <- rotate_out$Q
      Zhat <- Q %*% rbind(t(Z2), Z3)
    }

    val$Zhat <- Zhat
    val$alphahat <- t(rotate_out$alpha)
    val$sig_diag <- rotate_out$sig_diag

    class(val) <- "backwash"

    return(val)
}

#' Second step of the backwash procedure.
#'
#' @param betahat_ols A vector of numerics. The oridinary least
#'     squares estimates of the regression coefficients.
#' @param S_diag A vector of positive numerics. The standard errors of
#'     \code{betahat_ols}.
#' @param alpha_tilde A matrix of numerics. The estimated coefficients
#'     of the confounders.
#' @param tau2_seq A vector of positive numerics. The known grid of
#'     prior mixing variances.
#' @param lambda_seq A vector of penalties for the estimate of the
#'     mixing proportions.
#' @inheritParams backwash
#'
#' @author David Gerard
#'
#' @export
backwash_second_step <- function(betahat_ols, S_diag, alpha_tilde,
                                 tau2_seq, lambda_seq,
                                 pi_init_type = c("zero_conc", "uniform", "random"),
                                 scale_var = TRUE, sprop = 0,
                                 var_inflate_pen = 0) {

    ## Check input -----------------------------------------------------------
    assertthat::assert_that(is.numeric(betahat_ols))
    assertthat::assert_that(all(S_diag > 0))
    assertthat::assert_that(is.matrix(alpha_tilde))
    assertthat::are_equal(length(betahat_ols), nrow(alpha_tilde))
    assertthat::are_equal(length(S_diag), nrow(alpha_tilde))
    assertthat::are_equal(length(tau2_seq), length(lambda_seq))
    assertthat::assert_that(is.logical(scale_var))

    pi_init_type <- match.arg(pi_init_type)

    p <- length(betahat_ols)
    nfac <- ncol(alpha_tilde)

    ## Initialize parameters ------------------------------------------------
    eigen_alpha <- eigen(crossprod(alpha_tilde, alpha_tilde), symmetric = TRUE)
    a2_half_inv <- eigen_alpha$vectors %*% diag(1 / sqrt(eigen_alpha$values), nrow = length(eigen_alpha$values)) %*% t(eigen_alpha$vectors)
    Amat <- alpha_tilde %*% a2_half_inv

    ## m1 <- Amat %*% t(Amat)
    ## m2 <- alpha_tilde %*% solve(t(alpha_tilde) %*% alpha_tilde) %*% t(alpha_tilde)
    ## all(abs(m1 - m2) < 10 ^ -14)

    M <- length(tau2_seq)
    zero_spot <- which(abs(tau2_seq) < 10 ^ -14)
    pivec <- initialize_mixing_prop(pi_init_type = pi_init_type, zero_spot = zero_spot, M = M)

    ash_args <- list()
    ash_args$betahat   <- c(betahat_ols)
    ash_args$sebetahat <- c(sqrt(S_diag))
    ashout <- do.call(what = ashr::ash.workhorse, args = ash_args)
    mubeta <- matrix(ashr::get_pm(ashout), ncol = 1)

    ASA <- crossprod(Amat, diag(1 / S_diag) %*% Amat)
    muv <- tcrossprod(solve(ASA), diag(1 / S_diag) %*% Amat) %*% (betahat_ols - mubeta)

    xi  <- 1
    phi <- 1

    ## One round of updates to finish initializing before sending it to SQUAREM
    qbout <- back_update_qbeta(betahat_ols = betahat_ols, S_diag = S_diag, Amat = Amat, pivec = pivec,
                               tau2_seq = tau2_seq, muv = muv, xi = xi, phi = phi)
    mubeta <- qbout$mubeta
    mubeta_matrix <- qbout$mubeta_matrix
    sig2beta_matrix <- qbout$sig2beta_matrix
    gamma_mat <- qbout$gamma_mat

    pivec <- back_update_pi(gamma_mat = gamma_mat, lambda_seq = lambda_seq)

    qvout <- back_update_v(betahat_ols = betahat_ols, S_diag = S_diag, Amat = Amat, mubeta = mubeta,
                           xi = xi, phi = phi)

    muv <- qvout$muv
    Sigma_v <- qvout$Sigma_v

    phi <- back_update_phi(betahat_ols = betahat_ols, S_diag = S_diag, Amat = Amat,
                           mubeta = mubeta, muv = muv, Sigma_v= Sigma_v)

    if (scale_var) {
      xi <- back_update_xi(betahat_ols = betahat_ols, S_diag = S_diag, Amat = Amat, mubeta = mubeta,
                           mubeta_matrix = mubeta_matrix, sig2beta_matrix = sig2beta_matrix,
                           gamma_mat = gamma_mat, muv = muv, Sigma_v = Sigma_v, phi = phi,
                           var_inflate_pen = var_inflate_pen)
    }

    par_vec <- c(pivec, mubeta_matrix, sig2beta_matrix, gamma_mat, muv, Sigma_v, phi, xi)

    sqout <- SQUAREM::squarem(par = par_vec, fixptfn = back_fix, objfn = back_obj,
                              betahat_ols = betahat_ols,
                              S_diag = S_diag, Amat = Amat, tau2_seq = tau2_seq,
                              lambda_seq = lambda_seq,
                              scale_var = scale_var,
                              control = list(tol = 10 ^ -4),
                              var_inflate_pen = var_inflate_pen)

    ## Get returned parameters -----------------------------------------------------------

    pivec           <- sqout$par[1:M] ## M vector
    mubeta_matrix   <- matrix(sqout$par[(M + 1):(M + p * M)], nrow = p) ## p by M matrix
    sig2beta_matrix <- matrix(sqout$par[(M + p * M + 1): (M + 2 * p * M)], nrow = p) ## another p by M matrix
    gamma_mat       <- matrix(sqout$par[(M + 2 * p * M + 1):(M + 3 * p * M)], nrow = p) ## yet another p by M matrix
    muv             <- matrix(sqout$par[(M + 3 * p * M + 1):(M + 3 * p * M + nfac)], ncol = 1) ## an nfac matrix
    Sigma_v         <- matrix(sqout$par[(M + 3 * p * M + nfac + 1):(M + 3 * p * M + nfac + nfac ^ 2)], nrow = nfac) ## an nfac by nfac matrix
    phi             <- sqout$par[length(sqout$par) - 1]
    xi              <- sqout$par[length(sqout$par)]
    mubeta          <- rowSums(mubeta_matrix * gamma_mat)

    ## Posterior Summaries ---------------------------------------------------------------
    PosteriorMean <- mubeta
    lfdr          <- gamma_mat[, zero_spot]
    pi0           <- pivec[zero_spot]
    qvalue        <- ashr::qval.from.lfdr(lfdr)
    PositiveProb  <- rowSums(gamma_mat * (1 - stats::pnorm(q = 0, mean = mubeta_matrix, sd = sqrt(sig2beta_matrix))))
    NegativeProb  <- 1 - PositiveProb - lfdr
    ex2           <- rowSums(gamma_mat * (mubeta_matrix ^ 2 + sig2beta_matrix))
    PosteriorSD   <- ex2 - PosteriorMean ^ 2
    lfsr          <- pmin(PositiveProb, NegativeProb) + lfdr
    svalue        <- ashr::qval.from.lfdr(lfsr)

    ## modify posterior based on sprop ---------------------------------------------------
    ## Recall that betahat_ols, S_diag, and alpha_tilde were modified prior to being sent to
    ## backwash second step. We need to adjust some (but not all) posterior summaries.
    if (sprop > 0) {
      sgamma        <- S_diag ^ (sprop / (2 * (1 - sprop)))
      S_diag        <- S_diag ^ (1 / (1 - sprop))
      PosteriorMean <- PosteriorMean * sgamma
      PosteriorSD   <- PosteriorSD * sgamma
      betahat_ols   <- betahat_ols * sgamma
    }



    result <- data.frame(betahat = betahat_ols,
                         sebetahat = S_diag,
                         NegativeProb = NegativeProb,
                         PositiveProb = PositiveProb,
                         lfsr = lfsr,
                         svalue = svalue,
                         lfdr = lfdr,
                         qvalue = qvalue,
                         PosteriorMean = PosteriorMean,
                         PosteriorSD = PosteriorSD)

    return_list                      <- list()
    return_list$result               <- result
    return_list$elbo                 <- -1 * sqout$value.objfn
    return_list$xi                   <- xi
    return_list$phi                  <- phi
    return_list$z2hat                <- a2_half_inv %*% muv
    return_list$pi0                  <- pi0
    return_list$fitted_g             <- list()
    return_list$fitted_g$pivec       <- pivec
    return_list$fitted_g$tau2_seq    <- tau2_seq
    return_list$fitted_g$means       <- mubeta_matrix
    return_list$fitted_g$variances   <- sig2beta_matrix
    return_list$fitted_g$proportions <- gamma_mat

    return(return_list)
}


#' Fixed point iteration for BACKWASH.
#'
#' This is mostly so that I can use the SQUAREM package.
#'
#' @inheritParams backwash_second_step
#' @param Amat The A matrix for the variational EM.
#' @param tau2_seq The known grid of prior mixing variances.
#' @param par_vec A huge vector of parameters whose elements are in
#'     the following order: pivec, mubeta_matrix, sig2beta_matrix,
#'     gamma_mat, muv, Sigma_v, phi, xi
#' @param lambda_seq A vector of numerics greater than 1. The penalties for the prior mixing proportions.
#'
#' @author David Gerard
#'
back_fix <- function(par_vec, betahat_ols, S_diag, Amat, tau2_seq, lambda_seq, scale_var = TRUE,
                     var_inflate_pen = 0) {

  # Parse par_vec -----------------------------------------------------------
  p <- length(S_diag)
  nfac <- ncol(Amat)
  M <- length(tau2_seq)

  assertthat::are_equal(nrow(Amat), p)
  assertthat::are_equal(length(betahat_ols), p)
  assertthat::are_equal(length(tau2_seq), length(lambda_seq))
  assertthat::are_equal(length(par_vec), M + 3 * p * M + nfac + nfac ^ 2 + 2)

  pivec <- par_vec[1:M] ## M vector
  mubeta_matrix <- matrix(par_vec[(M + 1):(M + p * M)], nrow = p) ## p by M matrix
  sig2beta_matrix <- matrix(par_vec[(M + p * M + 1): (M + 2 * p * M)], nrow = p) ## another p by M matrix
  gamma_mat <- matrix(par_vec[(M + 2 * p * M + 1):(M + 3 * p * M)], nrow = p) ## yet another p by M matrix
  muv <- matrix(par_vec[(M + 3 * p * M + 1):(M + 3 * p * M + nfac)], ncol = 1) ## an nfac matrix
  Sigma_v <- matrix(par_vec[(M + 3 * p * M + nfac + 1):(M + 3 * p * M + nfac + nfac ^ 2)], nrow = nfac) ## an nfac by nfac matrix
  phi <- par_vec[length(par_vec) - 1]
  xi <- par_vec[length(par_vec)]
  mubeta <- rowSums(mubeta_matrix * gamma_mat)

  assertthat::assert_that(all(pivec >= 0))
  assertthat::are_equal(sum(pivec), 1)

  qbout <- back_update_qbeta(betahat_ols = betahat_ols, S_diag = S_diag, Amat = Amat, pivec = pivec,
                             tau2_seq = tau2_seq, muv = muv, xi = xi, phi = phi)
  mubeta <- qbout$mubeta
  mubeta_matrix <- qbout$mubeta_matrix
  sig2beta_matrix <- qbout$sig2beta_matrix
  gamma_mat <- qbout$gamma_mat

  pivec <- back_update_pi(gamma_mat = gamma_mat, lambda_seq = lambda_seq)

  qvout <- back_update_v(betahat_ols = betahat_ols, S_diag = S_diag, Amat = Amat, mubeta = mubeta,
                         xi = xi, phi = phi)

  muv <- qvout$muv
  Sigma_v <- qvout$Sigma_v

  phi <- back_update_phi(betahat_ols = betahat_ols, S_diag = S_diag, Amat = Amat,
                         mubeta = mubeta, muv = muv, Sigma_v= Sigma_v)

  if (scale_var){
    xi <- back_update_xi(betahat_ols = betahat_ols, S_diag = S_diag, Amat = Amat, mubeta = mubeta,
                         mubeta_matrix = mubeta_matrix, sig2beta_matrix = sig2beta_matrix,
                         gamma_mat = gamma_mat, muv = muv, Sigma_v = Sigma_v, phi = phi,
                         var_inflate_pen = var_inflate_pen)
  }

  par_vec <- c(pivec, mubeta_matrix, sig2beta_matrix, gamma_mat, muv, Sigma_v, phi, xi)

  return(par_vec)
}


#' Objective function for BACKWASH.
#'
#' This is mostly so that I can use the SQUAREM package.
#'
#' @inheritParams backwash_second_step
#' @param Amat The A matrix for the variational EM.
#' @param tau2_seq The known grid of prior mixing variances.
#' @param par_vec A huge vector of parameters whose elements are in
#'     the following order: pivec, mubeta_matrix, sig2beta_matrix,
#'     gamma_mat, muv, Sigma_v, phi, xi
#' @param lambda_seq A vector of numerics greater than 1. The
#'     penalties for the prior mixing proportions.
#'
#' @author David Gerard
back_obj <- function(par_vec, betahat_ols, S_diag, Amat, tau2_seq, lambda_seq, scale_var = TRUE,
                     var_inflate_pen = 0) {

  p <- length(S_diag)
  nfac <- ncol(Amat)
  M <- length(tau2_seq)

  assertthat::are_equal(nrow(Amat), p)
  assertthat::are_equal(length(betahat_ols), p)
  assertthat::are_equal(length(tau2_seq), length(lambda_seq))
  assertthat::are_equal(length(par_vec), M + 3 * p * M + nfac + nfac ^ 2 + 2)

  pivec <- par_vec[1:M] ## M vector
  mubeta_matrix <- matrix(par_vec[(M + 1):(M + p * M)], nrow = p) ## p by M matrix
  sig2beta_matrix <- matrix(par_vec[(M + p * M + 1): (M + 2 * p * M)], nrow = p) ## another p by M matrix
  gamma_mat <- matrix(par_vec[(M + 2 * p * M + 1):(M + 3 * p * M)], nrow = p) ## yet another p by M matrix
  muv <- matrix(par_vec[(M + 3 * p * M + 1):(M + 3 * p * M + nfac)], ncol = 1) ## an nfac matrix
  Sigma_v <- matrix(par_vec[(M + 3 * p * M + nfac + 1):(M + 3 * p * M + nfac + nfac ^ 2)], nrow = nfac) ## an nfac by nfac matrix
  phi <- par_vec[length(par_vec) - 1]
  xi <- par_vec[length(par_vec)]
  mubeta <- rowSums(mubeta_matrix * gamma_mat)

  assertthat::assert_that(all(pivec >= 0))
  assertthat::are_equal(sum(pivec), 1)

  elbo <- back_elbo(betahat_ols = betahat_ols, S_diag = S_diag,
                    Amat = Amat, tau2_seq = tau2_seq,
                    pivec = pivec, lambda_seq = lambda_seq,
                    mubeta = mubeta,
                    mubeta_matrix = mubeta_matrix,
                    sig2beta_matrix = sig2beta_matrix,
                    gamma_mat = gamma_mat, muv = muv,
                    Sigma_v = Sigma_v, phi = phi, xi = xi,
                    var_inflate_pen = var_inflate_pen)

  return(-1 * elbo)
}

#' Update for the variational density of beta
#'
#' @inheritParams backwash_second_step
#' @param Amat The A matrix for the variational EM.
#' @param pivec The current values of the mixing proportions.
#' @param tau2_seq The known grid of prior mixing variances.
#' @param muv A matrix of one column of numerics. The current mean of
#'     v.
#' @param xi A positive numeric. The current value of xi.
#' @param phi A numeric. The "g" hyperparameter.
#'
#' @author David Gerard
#'
back_update_qbeta <- function(betahat_ols, S_diag, Amat, pivec, tau2_seq, muv, xi, phi) {

  ## Check input ------------------------------------------------------------
  assertthat::assert_that(is.matrix(Amat))
  assertthat::assert_that(is.matrix(muv))
  assertthat::are_equal(length(betahat_ols), length(S_diag))
  assertthat::are_equal(length(betahat_ols), nrow(Amat))
  assertthat::are_equal(length(pivec), length(tau2_seq))
  assertthat::are_equal(ncol(Amat), nrow(muv))
  assertthat::are_equal(length(xi), 1)
  assertthat::are_equal(length(phi), 1)
  assertthat::assert_that(xi > 0)

  M <- length(tau2_seq)
  xiS <- xi * S_diag

  sig2beta_matrix <- 1 / outer(1 / xiS, 1 / tau2_seq, FUN = `+`)

  r_vec <- betahat_ols - phi * Amat %*% muv

  mubeta_matrix <- c(r_vec / xiS) * sig2beta_matrix
  ## diag(c(r_vec / (xi * S_diag))) %*% sig2beta_matrix

  dsds <- sqrt(outer(xiS, tau2_seq, FUN = `+`))
  dobs <- matrix(rep(r_vec, M), ncol = M, byrow = FALSE)
  dnorm_vals <- stats::dnorm(x = dobs, mean = 0, sd = dsds, log = TRUE)

  if (any(pivec < -10 ^ -12) | any(pivec > 1 + 10 ^ -12)) {
    gamma_mat <- matrix(NaN, nrow = length(betahat_ols), ncol = M)
  } else {
    ldmat <- sweep(x = dnorm_vals, MARGIN = 2, STATS = log(pivec), FUN = `+`)
    ldmat <- exp(ldmat - apply(ldmat, 1, max))
    ldmat[ldmat < -10^-12] <- 0
    gamma_mat <- ldmat / rowSums(ldmat)
  }


    ## temp <- exp(dnorm_vals) %*% diag(pivec)
    ## temp <- temp / rowSums(temp)
    ## gamma_mat <- temp
    ## assertthat::are_equal(temp, gamma_mat)

  mubeta <- rowSums(gamma_mat * mubeta_matrix)

  return(list(mubeta = mubeta, mubeta_matrix = mubeta_matrix, sig2beta_matrix = sig2beta_matrix,
              gamma_mat = gamma_mat))
}

#' Update for the prior mixing proportions.
#'
#' @param gamma_mat The current values of the variational mixing
#'     proportions. The number of columns is the number of
#'     observations and the number of rows is the number of mixture
#'     components. The rows must sum to one.
#' @param lambda_seq A vector of numerics greater than 1. The
#'     penalties on the pi's.
#'
#' @author David Gerard
#'
back_update_pi <- function(gamma_mat, lambda_seq) {

  assertthat::assert_that(is.matrix(gamma_mat))
  assertthat::are_equal(nrow(gamma_mat), length(lambda_seq))
  assertthat::assert_that(all(lambda_seq >= 1))

  gvec <- colSums(gamma_mat) + lambda_seq - 1
  gvec[gvec < 0] <- 0

  pivec <- gvec / sum(gvec)

  return(pivec)
}

#' Update for the variational density of v.
#'
#' @inheritParams back_update_qbeta
#' @param mubeta The current means of the betas.
#'
#' @author David Gerard
back_update_v <- function(betahat_ols, S_diag, Amat, mubeta, xi, phi) {

  nfac <- ncol(Amat)
  Sigma_v <- solve(crossprod(Amat, diag(1 / S_diag) %*% Amat) * (phi ^ 2) / xi + diag(nrow = nfac))
  muv     <- (phi / xi) * Sigma_v %*% crossprod(Amat, (betahat_ols - mubeta) / S_diag)

  return(list(muv = muv, Sigma_v = Sigma_v))
}

#' Update for the "g" hyperparameter.
#'
#' @inheritParams back_update_qbeta
#' @param mubeta The current means of the betas.
#' @param Sigma_v The current covarianc matrix of the latent v.
#'
#' @author David Gerard
#'
back_update_phi <- function(betahat_ols, S_diag, Amat, mubeta, muv, Sigma_v) {

  ASA <- crossprod(Amat, diag(1 / S_diag) %*% Amat)
  numerator_val <- crossprod(muv, crossprod(Amat, (betahat_ols - mubeta) / S_diag))
  denominator_val1 <- crossprod(muv, ASA) %*% muv
  denominator_val2 <- sum(ASA * Sigma_v)
  ## assertthat::are_equal(denominator_val2, sum(diag(ASA %*% Sigma_v)))

  phi <- c(numerator_val / (denominator_val1 + denominator_val2))
  return(phi)
}

#' Update for the variance scaling parameter.
#'
#' @inheritParams back_update_qbeta
#' @param mubeta The current means of the betas
#' @param mubeta_matrix The current mixing means of the variational
#'     densities of the betas.
#' @param sig2beta_matrix The current mixing variances of the
#'     variational densities of the betas.
#' @param gamma_mat The current mixing proportions of the variational
#'     densities of the betas.
#' @param Sigma_v The current covariance matrix of the latent v.
#' @param phi The current "g" hyperparameter.
#' @param var_inflate_pen The penalty to apply on the variance inflation parameter.
#'     Defaults to 0, but should be something non-zero when \code{alpha = 1}
#'     and \code{scale_var = TRUE}.
#'
back_update_xi <- function(betahat_ols, S_diag, Amat, mubeta, mubeta_matrix, sig2beta_matrix,
                           gamma_mat, muv, Sigma_v, phi, var_inflate_pen = 0) {

  t1 <- sum((betahat_ols ^ 2) / S_diag)

  t2 <- sum(rowSums((mubeta_matrix ^ 2 + sig2beta_matrix) * gamma_mat) / S_diag)

  ASA <- crossprod(Amat, diag(1 / S_diag) %*% Amat)
  t3 <- (crossprod(muv, ASA) %*% muv + sum(ASA * Sigma_v)) * phi ^ 2

  t4 <- 2 * sum(betahat_ols * mubeta / S_diag)

  Amuv <- Amat %*% muv
  t5 <- 2 * phi * sum(betahat_ols * Amuv / S_diag)

  t6 <- 2 * phi * sum(mubeta * Amuv / S_diag)

  xi <- c((t1 + t2 + t3 - t4 - t5 + t6) / length(betahat_ols)) +
    2 * var_inflate_pen / length(betahat_ols) ## inflation caused by penalty

  return(xi)
}

#' The Evidence lower bound.
#'
#' @inheritParams back_update_qbeta
#' @inheritParams back_update_xi
#' @param lambda_seq A vector of numerics greater than 1. The
#'     penalties on the pi's.
#' @param var_inflate_pen The penalty to apply on the variance inflation parameter.
#'     Defaults to 0, but should be something non-zero when \code{alpha = 1}
#'     and \code{scale_var = TRUE}.
#'
#' @author David Gerard
#'
back_elbo <- function(betahat_ols, S_diag, Amat, tau2_seq, pivec, lambda_seq, mubeta,
                      mubeta_matrix, sig2beta_matrix,
                      gamma_mat, muv, Sigma_v, phi, xi, var_inflate_pen = 0) {

  if (any(pivec < -10 ^ -12) | any(pivec > 1 + 10 ^ -12)) {
    return(-Inf)
  } else if (any(gamma_mat < -10^-12) | any(gamma_mat > 1 + 10 ^ -12)) {
    return(-Inf)
  }


  assertthat::are_equal(rowSums(mubeta_matrix * gamma_mat), mubeta)

  zero_spot <- which(abs(tau2_seq) < 10 ^ -14)
  assertthat::are_equal(length(zero_spot), 1)
  zeropi <- abs(pivec) < 10 ^ -10

  p <- length(betahat_ols)

  ## First summand ----------------------------------------------------------
  s1 <- - (p / 2) * log(xi)

  ## Second summand ---------------------------------------------------------
  t1 <- sum((betahat_ols ^ 2) / S_diag)

  t2 <- sum(rowSums((mubeta_matrix ^ 2 + sig2beta_matrix) * gamma_mat) / S_diag)

  ASA <- crossprod(Amat, diag(1 / S_diag) %*% Amat)
  t3 <- (crossprod(muv, ASA) %*% muv + sum(ASA * Sigma_v)) * phi ^ 2
  ## assertthat::are_equal(sum(diag(ASA %*% Sigma_v)), sum(ASA * Sigma_v))

  t4 <- - 2 * sum(betahat_ols * mubeta / S_diag)

  Amuv <- Amat %*% muv
  t5 <-  - 2 * phi * sum(betahat_ols * Amuv / S_diag)

  t6 <- 2 * phi * sum(mubeta * Amuv / S_diag)

  s2 <- - c(t1 + t2 + t3 + t4 + t5 + t6) / (2 * xi)

  ## Third summand ----------------------------------------------------------
  tempmat1 <- -1 * sweep(x = mubeta_matrix ^ 2 + sig2beta_matrix, MARGIN = 2, STATS = 1 / (2 * tau2_seq), FUN = `*`)
  tempmat2 <- sweep(x = tempmat1, MARGIN = 2, STATS = - log(tau2_seq) / 2 + log(pivec), FUN = `+`) - log(2 * pi) / 2
  ## assertthat::are_equal((mubeta_matrix ^ 2 + sig2beta_matrix)[1, ] / (2 * tau2_seq), -1 * tempmat1[1,])

  ## deal with pointmass and zero pivals
  tempmat2[, zero_spot] <- log(pivec[zero_spot])
  tempmat2[, zeropi] <- 0

  s3 <- sum(tempmat2 * gamma_mat)

  ## Fourth and fifth summand -----------------------------------------------
  s4 <- - sum(muv ^ 2) / 2

  s5 <- - sum(diag(Sigma_v)) / 2

  ## Sixth summand ---------------------------------------------------------
  s6 <- sum(((lambda_seq - 1) * log(pivec))[!zeropi])

  ## Seventh summand --------------------------------------------------------
  s7 <- determinant(Sigma_v, logarithm = TRUE)$modulus / 2
  ## s71 <- - sum(log(eigen(Sigma_v, symmetric = TRUE, only.values = TRUE)$values)) / 2
  ## assertthat::are_equal(s7, sum(log(eigen(Sigma_v, symmetric = TRUE, only.values = TRUE)$values)) / 2)



  ## Eighth summand ---------------------------------------------------------
  tmat <- (log(gamma_mat) - log(2 * pi) / 2 - log(sig2beta_matrix) / 2 -  1/2)
  tmat[sig2beta_matrix < 10 ^ -14] <- log(gamma_mat[sig2beta_matrix < 10 ^ -14]) ## entropy of pointmasses
  tmat[gamma_mat < 10 ^ -14] <- 0 ## no support
  s8 <- - sum(tmat * gamma_mat)

  ## variance inflation penalty
  vpen <- -var_inflate_pen / xi

  ## Compute ELBO -----------------------------------------------------------

  elbo <- s1 + s2 + s3 + s4 + s5 + s6 + s7 + s8 + vpen

  return(elbo)

}
