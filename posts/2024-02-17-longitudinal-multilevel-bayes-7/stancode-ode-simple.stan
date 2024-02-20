//
// Stan code for fitting an ODE model to time-series data
//

// this code block defines the ODE model
    // I'm removing the last letter from each variable name
    // just to avoid potential conflicts with bulit-in names of Stan
    // such as beta for a beta distribution
    // it might not matter, but I wanted to be safe
functions {
  vector odemod(real t,
             vector y,
             real alph, 
             real bet, 
             real gamm, 
             real et) {
    vector[3] dydt;
    dydt[1] = - bet * y[1] * y[3];
    dydt[2] = bet * y[1] * y[3] - gamm * y[2];
    dydt[3] = alph * y[2] - et * y[3];
    return dydt;
  }
}

data{
   int<lower = 1> Ntot; //number of observations for each individual
   int<lower = 1> Nind; //number of individuals
   int<lower = 1> Ndose; //number of dose levels
   array[Nind] int Nobs; //number of observations for each individual
   array[Ntot] real outcome; //virus load
   array[Ntot] real time; // times at which virus load is measured
   real tstart; //starting time for model
   array[Ntot] int id;  //vector of person IDs to keep track which data points belong to whom
   array[Nind] int dose_level; //dose level for each individual, needed to index V0 starting values
   //everything below are variables that contain values for prior distributions
   real a0_mu; 
   real b0_mu;
   real g0_mu;
   real e0_mu;
   real a0_sd;
   real b0_sd;
   real g0_sd;
   real e0_sd;
   real V0_mu;
   real V0_sd;
}

// specifying where in the vector each individual starts and stops
transformed data {
  array[Nind] int start;
  array[Nind] int stop;
  start[1] = 1;
  stop[1] = Nobs[1];
  for(i in 2:Nind) {
    start[i] = start[i - 1] + Nobs[i - 1];
    stop[i] = stop[i - 1] + Nobs[i];
  }
}

parameters{
    // population variance
    real<lower=0> sigma;
    // individual-level  parameters
    vector[Nind] a0;
    vector[Nind] b0;
    vector[Nind] g0;
    vector[Nind] e0;
    // starting value of virus for individuals in each dose group
    // is being estimated
    vector[Ndose] V0;
}

// Generated/intermediate parameters
transformed parameters{

    // main model parameters
    // this is coded such that each individual can have their own value
    // however, in this iteration of the code, the values only differ by dose level
    // a later iteration of the code will include individal level variation
    // I'm removing the last letter from each variable name
    // just to avoid potential conflicts with bulit-in names of Stan
    // such as beta for a beta distribution
    // it might not matter, but I wanted to be safe
    vector[Nind] alph;
    vector[Nind] bet;
    vector[Nind] gamm;
    vector[Nind] et;
    // predicted virus load from model
    vector[Ntot] virus_pred; 
    // time series for all 3 ODE model variables
    array[Ntot] vector[3] y_all;
    // starting conditions for ODE model
    vector[3] ystart;

    // loop over all individuals
    for ( i in 1:Nind ) {

      // compute main model parameters
      // here just exponentiated version of estimated parameters
      alph[i] = exp(a0[i]) ;
      bet[i] =  exp(b0[i]) ;
      gamm[i] =  exp(g0[i]) ;
      et[i] =  exp(e0[i]) ;
     
      // starting value for virus depends on dose 
      // we are fitting/running model with variables on a log scale
      ystart = [log(1e8),0,V0[dose_level[i]]]';
     
     // run ODE for each individual
      y_all[start[i]:stop[i]] = ode_rk45(
        odemod,      // name of ode function
        ystart,      // initial state
        tstart,      // initial time
        time[start[i]:stop[i]],  // observation times - here same for everyone
        alph[i], // model parameters - exponentiated to enforce positivity 
        bet[i], 
        gamm[i], 
        et[i] 
        );
    
      for (j in 1:Nobs[i]) {
          virus_pred[start[i] + j - 1] = y_all[start[i] + j - 1, 3];
      }
    } // end loop over each individual    
} // end transformed parameters block


model{

        // residual population variation
    sigma ~ exponential( 1 ); 
    // average dose-dependence of each ODE model parameter
    a0 ~ normal( a0_mu , a0_sd); 
    b0 ~ normal( b0_mu , b0_sd);
    g0 ~ normal( g0_mu,  g0_sd);
    e0 ~ normal( e0_mu , e0_sd);
    // prior for virus load starting value 
    V0 ~ normal(V0_mu, V0_sd);

    // distribution of outcome (virus load)
    // all computations to get the time-series trajectory for the outcome are done  
    // inside the transformed parameters block
    outcome ~ normal( virus_pred , sigma );

}

// for model diagnostics and exploration
generated quantities {
    // define quantities that are computed in this block
    vector[Ntot] ypred;
    vector[Ntot] log_lik;
    real<lower=0> sigma_prior;
    real a0_prior;
    real b0_prior;
    real g0_prior;
    real e0_prior;
    real V0_prior;     
    
    
    // this is so one can plot priors and compare with posterior later   
    // simulate the priors
    sigma_prior = exponential_rng( 1 );
    a0_prior = normal_rng( a0_mu , a0_sd);
    b0_prior = normal_rng( b0_mu , b0_sd);
    g0_prior = normal_rng( g0_mu , g0_sd);
    e0_prior = normal_rng( e0_mu , e0_sd);
    V0_prior = normal_rng( V0_mu , V0_sd);


  // compute log-likelihood and predictions
    for(i in 1:Ntot)
    {
      log_lik[i] = normal_lpdf(outcome[i] | virus_pred[i], sigma);
      ypred[i] = normal_rng(virus_pred[i], sigma);
    }
} //end generated quantities block 

