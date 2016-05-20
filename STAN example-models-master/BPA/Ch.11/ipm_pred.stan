// Integrated population model

functions {
  /**
   * Return log probability of Poisson distribution.
   * Outcome n may be a real value; for compatibility with Win/OpenBUGS.
   *
   * @param n      Outcome
   * @param lambda Mean
   *
   * @return Log probability
   */
  real real_poisson_log(real n, real lambda) {
    real lp;

    if (lambda < 0) {
      reject("lambda must be non-negative; found lambda=", lambda);
    } else if (n < 0.0) {
      reject("n must not be negative; found n=", n);
    } else {
      return n * log(lambda) - lambda - lgamma(n + 1);
    }
    return negative_infinity();
  }

  /**
   * Return log probability of binomial distribution.
   * Outcome n may be a real value; for compatibility with Win/OpenBUGS.
   *
   * @param n     Outcome
   * @param N     Size
   * @param theta Probability
   *
   * @return Log probability
   */
  real real_binomial_log(real n, real N, real theta) {
    real lp;

    if (N < 0) {
      reject("N must be non-negative; found N=", N);
    } else if (theta < 0 || theta > 1) {
      reject("theta must be in [0,1]; found theta=", theta);
    } else if (n < 0 || n > N) {
      reject("n must be in [0:N]; found n=", n);
    } else {
      return binomial_coefficient_log(N, n)
        + n * log(theta) + (N - n) * log(1.0 - theta);
    }
    return negative_infinity();
  }

  /**
   * Return m-array
   *
   * @param nyears Number of years
   * @param sjuv   Survival probability of juveniles
   * @param sad    Survival probability of adults
   * @param p      Recapture probability
   *
   * @return m-array
   */
  vector[] marray(int nyears, vector sjuv, vector sad, vector p)  {
    vector[nyears] pr[2*(nyears-1)];
    vector[nyears] q;

    q <- 1.0 - p;

    // m-array cell probabilities for juveniles
    for (t in 1:(nyears - 1)) {
      // Main diagonal
      pr[t, t] <- sjuv[t] * p[t];

      // Above main diagonal
      for (j in (t + 1):(nyears - 1))
        pr[t, j] <- sjuv[t] * prod(sad[(t + 1):j])
          * prod(q[t:(j - 1)]) * p[j];

      // Below main diagonal
      for (j in 1:(t - 1))
        pr[t, j] <- 0.0;

      // Last column: probability of non-recapture
      pr[t,nyears] <- 1.0 - sum(pr[t, 1:(nyears - 1)]);
    } //t

      // m-array cell probabilities for adults
    for (t in 1:(nyears - 1)) {

      // Main diagonal
      pr[t + nyears - 1, t] <- sad[t] * p[t];
      // Above main diagonal
      for (j in (t + 1):(nyears - 1))
        pr[t + nyears - 1, j] <- prod(sad[t:j])
          * prod(q[t:(j - 1)]) * p[j];

      // Below main diagonal
      for (j in 1:(t - 1))
        pr[t + nyears - 1, j] <- 0.0;

      // Last column
      pr[t + nyears - 1, nyears] <- 1.0
        - sum(pr[t + nyears - 1, 1:(nyears - 1)]);
    } //t
    return pr;
  }
}

data {
  int nyears;                    // Number of years
  vector[nyears] y;              // Population counts
  int J[nyears-1];               // Total number of nestings recorded
  int R[nyears-1];               // Annual number of surveyed broods
  int m[2*(nyears-1), nyears];   // m-array
  int<lower=1> t_pred;           // Number of years to predict
}

parameters {
  real<lower=0> sigma_y;           // Observation error
  vector<lower=0>[nyears] N1;      // Number of 1-year juveniles
  vector<lower=0>[nyears] Nad;     // Number of adults
  real<lower=0,upper=1> mean_sjuv; // Mean survival prob. juveniles
  real<lower=0,upper=1> mean_sad;  // Mean survival prob. adults
  real<lower=0,upper=1> mean_p;    // Mean recapture prob.
  real<lower=0> mean_fec;          // Mean productivity
}

transformed parameters {
  vector<lower=0,upper=1>[nyears] sjuv;
  vector<lower=0,upper=1>[nyears] sad;
  vector<lower=0,upper=1>[nyears] p;
  vector<lower=0>[nyears] f;
  vector<lower=0>[nyears] Ntot;
  simplex[nyears] pr[2*(nyears-1)];
  vector<lower=0>[nyears-1] rho;

  // Survival and recapture probabilities, as well as productivity
  for (t in 1:nyears) {
    sjuv[t] <- mean_sjuv;
    sad[t] <- mean_sad;
    p[t] <- mean_p;
    f[t] <- mean_fec;
  }

  // Total number of individuals
  for (t in 1:nyears)
    Ntot[t] <- Nad[t] + N1[t];

  // m-array
  pr <- marray(nyears, sjuv, sad, p);

  // Productivity
  for (t in 1:(nyears - 1))
    rho[t] <- R[t] * f[t];
}

model {
  // Priors
  // Initial population sizes
  // Constraints ensure truncated normal (> 0)
  N1[1] ~ normal(100, 100);
  Nad[1] ~ normal(100, 100);

  // Proper flat priors [0, 1] are implicitly used on mean_sjuv, mean_sad
  // and mean_p.
  // Improper flat priors are implicitly used on sigma_y and mean_fec.

  // Likelihood for population population count data (state-space model)
  // System process
  for (t in 2:nyears) {
    real mean1;

    mean1 <- f[t - 1] / 2 * sjuv[t - 1] * Ntot[t - 1];
    N1[t] ~ real_poisson(mean1);
    Nad[t] ~ real_binomial(Ntot[t - 1], sad[t - 1]);
  }

  // Observation process
  y ~ normal(Ntot, sigma_y);

  // Likelihood for capture-recapture data: CJS model (2 age classes)
  // Multinomial likelihood
  for (t in 1:(2 * (nyears - 1))) {
    m[t] ~ multinomial(pr[t]);
   }

  // Likelihood for productivity data: Poisson regression
  J ~ poisson(rho);
}

generated quantities {
  // Number of individuals are assigned as integer values
  // in this block
  vector<lower=0>[nyears-1] lambda;  // Population growth rate
  real<lower=0> sigma2_y;
  vector<lower=0,upper=1>[t_pred] sjuv_pred;
  vector<lower=0,upper=1>[t_pred] sad_pred;
  vector<lower=0,upper=20>[t_pred] f_pred;
  int<lower=0> N1_pred[t_pred];
  int<lower=0> Nad_pred[t_pred];
  int<lower=0> Ntot_pred[t_pred];
  int<lower=0> Ntot0;

  for (t in 1:(nyears - 1)) {
    lambda[t] <- Ntot[t+1] / Ntot[t];
  }
  sigma2_y <- square(sigma_y);

  // Prediction
  {
    int ind;
    int UP;
    real mean1;

    for (t in 1:t_pred) {
      sjuv_pred[t] <- mean_sjuv;
      sad_pred[t] <- mean_sad;
      f_pred[t] <- mean_fec;
    }
    // Ntot0 <- Ntot[nyears]; assign an integer value
    UP <- 10000;
    ind <- 1;
    while (ind < Ntot[nyears] && ind < UP) {
      ind <- ind + 1;
    }
    if (ind == UP) {
      reject("The variable ind reached upper bounds:", ind);
    } else {
      Ntot0 <- ind - 1;
    }

    mean1 <- f[nyears] / 2.0 * sjuv[nyears] * Ntot0;
    N1_pred[1] <- poisson_rng(mean1);
    Nad_pred[1] <- binomial_rng(Ntot0, sad[nyears]);
    Ntot_pred[1] <- N1_pred[1] + Nad_pred[1];
    for (t in 2:t_pred) {
      mean1 <- f_pred[t - 1] / 2.0 * sjuv_pred[t - 1] * Ntot_pred[t - 1];
      N1_pred[t] <- poisson_rng(mean1);
      Nad_pred[t] <- binomial_rng(Ntot_pred[t - 1], sad_pred[t - 1]);
      Ntot_pred[t] <- N1_pred[t] + Nad_pred[t];
    }
  }
}
