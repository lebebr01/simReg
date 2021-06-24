#' Parses tidy formula simulation syntax
#' 
#' A function that parses the formula simulation syntax in order to simulate data.
#' 
#' @param sim_args A named list with special model formula syntax. See details and examples
#'   for more information. The named list may contain the following:
#'   \itemize{
#'     \item fixed: This is the fixed portion of the model (i.e. covariates)
#'     \item random: This is the random portion of the model (i.e. random effects)
#'     \item error: This is the error (i.e. residual term).
#'   }
#' 
#' @export
#' 
#' 
parse_formula <- function(sim_args) {
  
  outcome <- sim_args[['formula']] %>%
    as.character() %>%
    .[2]
  
  fixed <- sim_args[['formula']] %>%
    as.character() %>%
    .[3] %>%
    gsub("\\+\\s*(\\s+|\\++)\\(.*?\\)", "", .) %>%
    gsub("^\\s+|\\s+$", "", .) %>%
    paste0("~", .) %>%
    as.formula()
  
  randomeffect <- sim_args[['formula']] %>%
    as.character() %>%
    .[3] %>%
    regmatches(gregexpr("(\\+|\\s+)\\(.*?\\)", .)) %>%
    unlist() %>%
    gsub("^\\s+|\\s+$", "", .)
  
  list(outcome = outcome, 
       fixed = fixed,
       randomeffect = randomeffect)
}

#' Parses random effect specification
#' 
#' @param formula Random effect formula already parsed by \code{\link{parse_formula}}
#' 
#' @export 
parse_randomeffect <- function(formula) {
  
  cluster_id_vars <- lapply(seq_along(formula), function(xx) strsplit(formula, "\\|")[[xx]][2]) %>%
    unlist() %>%
    gsub("\\)", "", .) %>%
    gsub("^\\s+|\\s+$", "", .)
  
  random_effects <- lapply(seq_along(formula), function(xx) strsplit(formula, "\\|")[[xx]][1]) %>%
    unlist() %>%
    gsub("\\(", "", .) %>%
    gsub("^\\s+|\\s+$", "", .) %>%
    paste0('~', .)
  
  list(
    cluster_id_vars = cluster_id_vars,
    random_effects = random_effects
  )

}

#' Parse Cross-classified Random Effects
#' 
#' @param sim_args Simulation arguments
#' @param random_formula_parsed This is the output from 
#'   \code{\link{parse_randomeffect}}.
#' 
#' @export
parse_crossclass <- function(sim_args, random_formula_parsed) {
  cross_class_re <- lapply(seq_along(sim_args[['randomeffect']]), 
                           function(xx) 
                             sim_args[['randomeffect']][[xx]][['cross_class']])
  cross_class_re <- unlist(lapply(seq_along(cross_class_re), function(xx)  
    !is.null(cross_class_re[[xx]])))
  num_res <- lapply(lapply(seq_along(random_formula_parsed[['random_effects']]), 
                           function(xx) 
                             unlist(strsplit(random_formula_parsed[['random_effects']][xx], '\\+'))), 
                    length)
  num_res <- unlist(lapply(seq_along(num_res), function(xx) 
    rep(random_formula_parsed[['cluster_id_vars']][xx], num_res[[xx]])))
  
  cross_class_idvars <- num_res[cross_class_re]
  
  list(cross_class_idvars = cross_class_idvars,
       num_res = num_res,
       cross_class_re = cross_class_re
  )
}

#' Parse power specifications
#' 
#' @param sim_args A named list with special model formula syntax. See details and examples
#'   for more information. The named list may contain the following:
#'   \itemize{
#'     \item fixed: This is the fixed portion of the model (i.e. covariates)
#'     \item random: This is the random portion of the model (i.e. random effects)
#'     \item error: This is the error (i.e. residual term).
#'   }
#' @param samp_size The sample size pulled from the simulation arguments or the 
#'  power model results when vary_arguments is used.
#' @importFrom dplyr quo
#' @export 
parse_power <- function(sim_args, samp_size) {
  
  if(is.null(sim_args[['power']][['direction']]) || sim_args[['power']][['direction']] %ni% c('lower', 'upper')) {
    number_tails <- 2
  } else {
    number_tails <- 1
  }
  
  if(is.null(sim_args[['power']][['direction']])) {
    tail_direction <- 'two-tailed'
  } else {
    tail_direction <- sim_args[['power']][['direction']]
  }
  
  if(is.null(sim_args[['power']][['dist']])) {
    stat_dist <- 'qnorm'
  } else {
    stat_dist <- sim_args[['power']][['dist']]
  }
  
  if(is.null(sim_args[['power']][['alpha']])) {
    alpha <- 0.05
  } else {
    alpha <- sim_args[['power']][['alpha']]
  }
  
  if(tail_direction == 'lower') {
    lower_tail <- TRUE
  } else {
    lower_tail <- FALSE
  }
  
  if(is.null(sim_args[['power']][['opts']])) {
    opts <- NULL
  } else {
    opts <- sim_args[['power']][['opts']]
  }
  
  alpha <- alpha / number_tails
  
  if(is.null(sim_args[['power']][['opts']][['df']]) & stat_dist == 'qt') {
    df <- purrr::map(samp_size, `-`, 1)
    
    test_statistic <- lapply(seq_along(df), function(xx) {
      purrr::invoke(stat_dist, 
                  p = alpha, 
                  lower.tail = lower_tail,
                  df = df[[xx]],
                  opts)
    })
  } else {
    test_statistic <- purrr::invoke(stat_dist, 
                                  p = alpha, 
                                  lower.tail = lower_tail,
                                  opts)
  }

  lapply(seq_along(test_statistic), function(xx) {
    list(test_statistic = test_statistic[[xx]],
         alpha = alpha, 
         number_tails = number_tails,
         direction = tail_direction,
         distribution = stat_dist
    )
  })
  
}

#' Parse varying arguments
#' 
#' @param sim_args A named list with special model formula syntax. See details and examples
#'   for more information. The named list may contain the following:
#'   \itemize{
#'     \item fixed: This is the fixed portion of the model (i.e. covariates)
#'     \item random: This is the random portion of the model (i.e. random effects)
#'     \item error: This is the error (i.e. residual term).
#'   }
#'   
#' @export
parse_varyarguments <- function(sim_args) {
  
  conditions <- expand.grid(sim_args[['vary_arguments']], KEEP.OUT.ATTRS = FALSE)
  if(any(sapply(conditions, is.list))) {
    loc <- sapply(conditions, is.list)
    simp_conditions <- conditions[loc != TRUE]
    list_conditions <- conditions[loc == TRUE]
    list_conditions <- lapply(seq_along(list_conditions), function(xx) 
      unlist(list_conditions[xx], recursive = FALSE))
    for(tt in seq_along(list_conditions)) {
      names(list_conditions[[tt]]) <- gsub("[0-9]*", "", names(list_conditions[[tt]]))
    }
    lapply(1:nrow(conditions), function(xx) c(sim_args, 
                                              simp_conditions[xx, , drop = FALSE], 
                                              do.call('c', lapply(seq_along(list_conditions), function(tt) 
                                                list_conditions[[tt]][xx]))
    ))
  } else {
    lapply(1:nrow(conditions), function(xx) c(sim_args, 
                                              conditions[xx, , drop = FALSE]))
  }
  
}


#' Parse correlation arguments
#' 
#' This function is used to parse user specified correlation attributes. 
#' The correlation attributes need to be in a dataframe to be processed 
#' internally. Within the dataframe, there are expected to be 3 columns, 
#' 1) names of variable/attributes, 2) the variable/attribute pair for 1, 
#' 3) the correlation. 
#' 
#' @param sim_args A named list with special model formula syntax. See details and examples
#'   for more information. The named list may contain the following:
#'   \itemize{
#'     \item fixed: This is the fixed portion of the model (i.e. covariates)
#'     \item random: This is the random portion of the model (i.e. random effects)
#'     \item error: This is the error (i.e. residual term).
#'     \item correlate: These are the correlations for random effects and/or
#'        fixed effects.
#'   }
#'   
#' @export
parse_correlation <- function(sim_args) {
  
  fixed_correlation <- dataframe2matrix(sim_args[['correlate']][['fixed']],
                                        corr_variable = 'corr', 
                                        var_names = c('x', 'y'))
  
  random_correlation <- dataframe2matrix(sim_args[['correlate']][['random']],
                                         corr_variable = 'corr',
                                         var_names = c('x', 'y'))
  
  list(fixed_correlation = fixed_correlation,
       random_correlation = random_correlation)
}

parse_fixedtype <- function(sim_args, names) {
  
  lapply(names, function(xx) sim_args[['fixed']][[xx]][['var_type']])
  
}

parse_fixedlevels <- function(sim_args, names) {
  lapply(names, function(xx) sim_args[['fixed']][[xx]]['levels'])
}
