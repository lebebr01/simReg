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

