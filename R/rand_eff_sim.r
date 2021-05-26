#' Function to simulate random effects.
#'
#' Input simulation parameters and returns random effects.
#'
#' Simulates random effects when
#' simulating a linear mixed model, both cross sectional and longitudinal. 
#' Allows the ability to simulate random effects from any 
#' specified distribution.
#'
#' @param random_var Variance of random effects. Must be same length as random.
#' @param n Cluster sample size.
#' @param rand_gen The generating function used (e.g. rnorm).
#' @param ther A vector of length two that specifies the theoretical mean and
#'              standard deviation of the rand_gen. This would commonly be used
#'              to standardize the generating variable to have a mean of 0 and
#'              standard deviation of 1 to meet model assumptions. The variable
#'              is then rescaled to have the variance specified by random_var.
#' @param ther_sim A TRUE/FALSE flag indicating whether the error simulation 
#'  function should be simulated, that is should the mean and standard deviation
#'  used for standardization be simulated.
#' @param cor_vars A vector of correlations between random effects. 
#' @param ... Additional values that need to be passed to the function
#'             called from rand_gen.
#' @export
sim_rand_eff <- function(random_var, n, rand_gen, ther = c(0, 1),
                         ther_sim = FALSE, cor_vars = NULL, ...) {
  
  # Look to edit this with match.arg and switch functions
  if(ther_sim) {
    ther_val <- sapply(X = 1000000, FUN = rand_gen, ...)
    ther <- c(mean(ther_val), sd(ther_val))
  }
  
  reff <- do.call('cbind', lapply(seq_along(random_var), function(xx)  
    standardize(sapply(n, FUN = rand_gen, ...),
                mean = ther[1], sd = ther[2])))
  
  if(is.null(cor_vars)) {
    reff <- reff %*% chol(diag(length(random_var)) * random_var)
  } else {
    c_mat <- matrix(nrow = length(random_var), ncol = length(random_var))
    diag(c_mat) <- 1
    c_mat[upper.tri(c_mat)] <- c_mat[lower.tri(c_mat)] <- cor_vars
    cov <- diag(sqrt(random_var)) %*% 
      c_mat %*% diag(sqrt(random_var))
    es <- eigen(cov, symmetric = TRUE)
    ev <- es$values
    reff <- t(es$vectors %*% diag(sqrt(pmax(ev, 0)), length(random_var)) %*% 
                t(reff))
  }
  
  reff
}

#' Cross Classified Generation
#' 
#' Input cross classified simulation parameters, output cross classified structure
#' as a function of the original id variables. This function currently only supports
#' a single (intercept) cross classified random effect.
#'  
#' @param num_ids Number of cross classified ids to generate. 
#' @param samp_size Sample size to generate, this is used to pass to the 
#'    \code{\link{sample}} function.
#' @param random_param A list of data generating characteristics used to generate
#'     the cross classified random effect. This function needs to include:
#'     \itemize{
#'       \item random_var The variance of the cross classified random effect.
#'       \item rand_gen The random generating function used.
#'     }
#'     Optional elements are:
#'    \itemize{
#'        \item ther: Theorectial mean and variance from rand_gen,
#'        \item ther_sim: Simulate mean/variance for standardization purposes,
#'        \item cor_vars: Correlation between random effects,
#'        \item ...: Additional parameters needed for rand_gen function.
#'    }
#'    See \code{\link{sim_rand_eff}} for additional parameters that can be passed.
#' @importFrom dplyr left_join
#' @export
cross_class <- function(num_ids, samp_size, random_param) {
  cross_ids <- data.frame(id = sample(1:num_ids, samp_size,
                                      replace = TRUE))
  
  cross_rand_eff <- data.frame(do.call(sim_rand_eff, 
                                       c(random_param,
                                         n = num_ids)))
  cross_rand_eff$id <- 1:num_ids
  
  cross_eff <- dplyr::left_join(cross_ids, cross_rand_eff, by = 'id')
  names(cross_eff) <- c('clustid_cross', 'c1')
  
  cross_eff
}

cross_class_sim <- function(num_ids, samp_size, col_names, ...) {
  cross_ids <- data.frame(id = sample(1:num_ids, samp_size,
                                      replace = TRUE))

  cross_rand_eff <- purrr::invoke_map('sim_cross',
                                      ...,
                                      num_ids = num_ids) %>%
    data.frame()
  cross_rand_eff$id <- 1:num_ids

  cross_eff <- dplyr::right_join(cross_rand_eff, cross_ids, by = 'id')
  names(cross_eff) <- col_names

  cross_eff
}

sim_cross <- function(num_ids, variance = NULL, dist = 'rnorm', 
                      ther_sim = FALSE, ...) {
  
  cont_var <- unlist(lapply(num_ids, FUN = dist, ...))

  
  if(!is.null(variance)) {
    if(ther_sim) {
      ther_val <- do.call(dist, c(list(n = 10000000), ...))
      ther <- c(mean(ther_val), sd(ther_val))
      
      cont_var <- standardize(cont_var, ther[1], ther[2])
    }
    if(length(ther_sim) == 2) {
      cont_var <- standardize(cont_var, ther_sim[1], ther_sim[2])
    }
    
    cont_var <- cont_var %*% chol(c(variance))
  }
  
  cont_var
}

#' Tidy random effect formula simulation
#' 
#' This function simulates the random portion of the model using a formula syntax.
#' 
#' @param data Data simulated from other functions to pass to this function. Can pass
#'  NULL if first in simulation string.
#' @param sim_args A named list with special model formula syntax. See details and examples
#'   for more information. The named list may contain the following:
#'   \itemize{
#'     \item fixed: This is the fixed portion of the model (i.e. covariates)
#'     \item random: This is the random portion of the model (i.e. random effects)
#'     \item error: This is the error (i.e. residual term).
#'   }
#' @param ... Other arguments to pass to error simulation functions.
#' 
#' @export 
simulate_randomeffect <- function(data, sim_args, ...) {
  
  random_formula <- parse_formula(sim_args)[['randomeffect']]

  random_formula_parsed <- parse_randomeffect(random_formula)
  
  random_effects_names <- names(sim_args[['randomeffect']])
  
  cross_class <- parse_crossclass(sim_args, random_formula_parsed)
  
  if(any(cross_class[['cross_class_re']])) {
    cross_loc <- grepl(cross_class[['cross_class_idvars']], 
                       random_formula_parsed[['cluster_id_vars']])
    
    cross_vars <- lapply(random_formula_parsed, '[', cross_loc)
    
    random_formula_parsed <- lapply(random_formula_parsed, '[', !cross_loc)
  }
  
  
  if(is.null(data)) {
    n <- sample_sizes(sim_args[['sample_size']])
    ids <- create_ids(n, 
                      c('level1_id', random_formula_parsed[['cluster_id_vars']]))
    Zmat <- purrr::invoke_map("sim_variable", 
                              sim_args[['randomeffect']][!cross_class[['cross_class_re']]],
                              n = n,
                              var_type = 'continuous'
    ) %>% 
      data.frame()
  } else {
    n <- compute_samplesize(data, sim_args)
    Zmat <- purrr::invoke_map("sim_variable", 
                              sim_args[['randomeffect']][!cross_class[['cross_class_re']]],
                              n = n,
                              var_type = 'continuous'
    ) %>% 
      data.frame()
  }
  
  names(Zmat) <- random_effects_names[!cross_class[['cross_class_re']]]
  
  if(any(cross_class[['cross_class_re']])) {
    cross_names <- c(random_effects_names[cross_class[['cross_class_re']]], 
                     cross_class[['cross_class_idvars']])
    
    args <- sim_args[['randomeffect']][cross_class[['cross_class_re']]]
    args[[1]]['var_level'] <- NULL
    args[[1]]['cross_class'] <- NULL
    
    cross_vars <- purrr::invoke_map('cross_class_sim',
                                    args,
                                    samp_size = sum(n[['level1']]),
                                    col_names = cross_names)
    Zmat <- data.frame(Zmat, cross_vars)
  }
  
  if(is.null(data)) {
    data.frame(Zmat, ids)
  } else {
    data.frame(data, Zmat)
  }
  
}

