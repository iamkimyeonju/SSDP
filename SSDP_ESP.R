ssdp_esp <- function(Q,
                     capacity,
                     S_disc = 100,
                     R_disc = 100,
                     Q_num = 3,
                     S_initial,
                     LWL,  
                     LHWL,
                     demand,
                     esp,
                     Cost_to_ESP,
                     transition,
                     probs = c(0.25,0.5,0.25)){
  
  frq <- frequency(Q)
  Q.probs <- probs # Q.probs란 Expectation 가중치에 들어갈 숫자
  Q_mat <- matrix(Q, byrow = TRUE, ncol = frq)
  prob <- seq(1/(2*Q_num),1, by=1/Q_num)
  Q_class_med <- esp
  fv <- Cost_to_ESP
  S_states <- seq(from = 0, to = capacity, by = capacity / S_disc)                   
  R_disc_x <- S_states
  Shell.array <- array(0,dim=c(length(S_states),length(R_disc_x),length(prob)))
  Cost_to_go <- vector("numeric",length=length(S_states))
  Results_mat <- matrix(0,nrow=length(S_states),ncol=frq)
  R_policy <- matrix(0,nrow=length(S_states),ncol=frq)
  Bellman <- R_policy
  R_policy_test <- R_policy
  F.n <- R_policy
  F.n_minus_1 <- R_policy
  F.n_minus_2 <- R_policy
  convergence <- matrix(1e-5,nrow=length(S_states),ncol=frq)
  
  
  # The sweep R function applies an operation (e.g. + or -) to a data matrix by row or by column.
  # MARGIN: Specifies typically whether the operation should be applied by row or by column. 
  # MARGIN = 1 operates by row; MARGIN = 2 operates by column; MARGIN = 3 operates by page.
  
  # aperm: Array Transposition
  # Transpose an array by permuting its dimensions and optionally resizing it.
  # 행열면 순서 바꾸는 함수
  
  repeat{
    for (t in 1:frq){  # forward recursive equation 
      R.cstr <- sweep(Shell.array, 3, Q_class_med[,t], "+") + sweep(Shell.array, 1, S_states, "+")
      # R.cstr = Q + S
      # t=1
      
      R.star <- aperm(apply(Shell.array, c(1, 3), "+", R_disc_x), c(2, 1, 3))      
      # R.star = R 
      
      R.star[,2:(R_disc + 1),][which(R.star[,2:(R_disc + 1),] > R.cstr[,2 : (R_disc + 1),])] <- NaN
      # 현재 가지고 있는 저수량보다 더 방류를 해줄수는 없기때문에 방류량이 더 큰 부분을 NaN 처리
      
      target <- demand[t]
      
      Deficit.arr <- (R.star - target)           # 부족량                                 
      Cost_arr <- ((abs(Deficit.arr))^2)         # 목적함수 값   B              
      
      #Deficit.arr <- (target - R.star)/target             # 부족량                                 
      #Deficit.arr[Deficit.arr <= 0] <- 0
      #Cost_arr <- Deficit.arr
      
      
      S.t_plus_1 <- R.cstr - R.star
      S.t_plus_1[which(S.t_plus_1 < 0)] <- 0      # S.t_plus_1이 마이너스를 가지지 않도록
      
      Implied_S_state <- round(1 + (S.t_plus_1 / capacity)*(length(S_states) - 1))
      # S+1 이 어느 index에 포함되는가?
      
      Implied_S_state[which(Implied_S_state > length(S_states))] <- length(S_states)
      
      Cost_to_go_from_esp <- fv[,t]
      Cost_to_go.arr <- array(Cost_to_go_from_esp[Implied_S_state],
                              dim = c(length(S_states), length(R_disc_x) , length(prob)))   
      
      #apply(sweep(ssdp_hist$Cost_to_ESP,c(1,2,3,4), transition,"*"),c(1,2,3),sum)
      
      Min_cost_arr <- Cost_arr + Cost_to_go.arr
      
      #Min_cost_arr <- array(Min_cost_arr1,Min_cost_arr2,Min_cost_arr3,dim=(c(101,101,3)))
      # 목적함수 값 과거와 현재 합친 f
      
      #Min_cost_arr_weighted <- sweep(Min_cost_arr, 3, Q.probs, "*")    
      Min_cost_arr_weighted <- Q.probs[1]*Min_cost_arr[,,1]+Q.probs[2]*Min_cost_arr[,,2]+Q.probs[3]*Min_cost_arr[,,3]
      # 기대값이 계산된 array Q.probs
      
      
      Min_cost_expected <- apply(Min_cost_arr_weighted, c(1, 2), sum)  
      # 행이랑 열 둘다 sum 결과로 한가지 array만 
      
      Bellman[,t] <- Cost_to_go   
      
      Cost_to_go <- apply(Min_cost_expected, 1, min, na.rm = TRUE)
      Results_mat[,t] <- Cost_to_go
      R_policy[,t] <- apply(Min_cost_expected, 1, which.min)
    }
    
    F.n_minus_2 <- F.n_minus_1
    F.n_minus_1 <- F.n
    F.n <- Results_mat
    
    message(paste("Convergence rate:",sum(abs(abs(F.n-F.n_minus_1)-abs(F.n_minus_1-F.n_minus_2)))))   
    if (sum(abs(abs(F.n-F.n_minus_1)-abs(F.n_minus_1-F.n_minus_2)) < convergence)
        == 
        length(S_states)*frq){
      break
    }
    R_policy_test <- R_policy
  }
  
  
  R_policy_M <- matrix(R_disc_x[R_policy],nrow=length(S_states),ncol=frq)
  
  # POLICY SIMULATION for all year -------------------------------------------------------
  
  S <- vector("numeric",length(Q) + 1); S[1] <- S_initial  
  R_rec <- vector("numeric",length(Q))
  Spill <- vector("numeric", length(Q))
  Q_mat <- matrix(Q, byrow = TRUE, ncol = frq)
  for (yr in 1:nrow(Q_mat)) {
    for (month in 1:frq) {
      t_index <- (frq * (yr - 1)) + month   
      S_state <- which.min(abs(S_states - S[t_index]))
      Qx <- Q_mat[yr,month]
      R <- R_disc_x[R_policy[S_state,month]]
      R_rec[t_index] <- R
      if ( (S[t_index] - R + Qx ) > capacity) {
        S[t_index + 1] <- capacity
        Spill[t_index] <- S[t_index] - R + Qx - capacity 
      }else{
        if ( (S[t_index] - R + Qx ) < 0) {
          S[t_index + 1] <- 0
          R_rec[t_index] <- max(0, S[t_index] + Qx )
        }else{
          S[t_index + 1] <- S[t_index] - R + Qx 
        }
      }
    }
  }
  S <- ts(S[1:(length(S) - 1)],start = start(Q),frequency = frq)
  R_rec <- ts(R_rec, start = start(Q), frequency = frq)
  Spill <- ts(Spill, start = start(Q), frequency = frq)
  total_penalty <- sum( ( (demand - as.vector(R_rec))) ^ 2)
  
  ################################################################################################
  # POLICY SIMULATION
  
  S_last <- vector("numeric",frq + 1); S_last[1] <- S_initial
  R_rec_last <- vector("numeric",frq)
  Spill_last <- vector("numeric", frq)
  Q_sim <- matrix(Q, byrow = TRUE, ncol = frq)
  Q_sim <- Q_sim[nrow(Q_sim),]
  
  for (month in 1:frq) { # month <- 1
    t_index <- month   
    S_state <- which.min(abs(S_states - S_last[t_index]))
    Qx_last <- Q_sim[month]
    R_last <- R_disc_x[R_policy[S_state,month]]
    R_rec_last[t_index] <- R_last
    
    if ( (S_last[t_index] - R_last + Qx_last) > LHWL) {
      S_last[t_index + 1] <- LHWL
      Spill_last[t_index] <- S_last[t_index] - R_last + Qx_last - LHWL
    }else{
      if ( (S_last[t_index] - R_last + Qx_last) < LWL) {    
        R_rec_last[t_index] <- 0 
        S_last[t_index + 1] <- S_last[t_index] - R_rec_last[t_index] + Qx_last
      }else{
        S_last[t_index + 1] <- S_last[t_index] - R_last + Qx_last
      }
    }
  }
  
  
  S_last <- ts(S_last[2:(length(S_last))],start = start(Q_sim),frequency = frq)
  R_rec_last <- ts(R_rec_last, start = start(Q_sim), frequency = frq)
  Spill_last <- ts(Spill_last, start = start(Q_sim), frequency = frq)
  total_penalty_last <- sum( (demand - as.vector(R_rec_last)) ^ 2)
  
  # COMPUTE RRV METRICS FROM SIMULATION RESULTS---------------------------------------
  
  deficit <- ts(round(1 - (R_rec_last / demand),5), start = start(Q_sim), frequency = frequency(Q_sim))
  rel_ann <- sum(aggregate(deficit, FUN = mean) == 0) /length(aggregate(deficit, FUN = mean))
  rel_time <- sum(deficit == 0) / length(deficit)
  rel_vol <- sum(R_rec_last) / sum(demand)
  fail.periods <- which(deficit > 0)
  if (length(fail.periods) == 0) {
    resilience <- NA
    vulnerability <- NA
  } else {
    if (length(fail.periods) == 1) {
      resilience <- 1
      vulnerability <- max(deficit)
    } else {
      resilience <- (sum(diff(which(deficit > 0)) > 1) + 1) / (length(which(deficit > 0)))
      fail.refs <- vector("numeric", length = length(fail.periods))
      fail.refs[1] <- 1
      for (j in 2:length(fail.periods)) {
        if (fail.periods[j] > (fail.periods[j - 1] + 1)) {
          fail.refs[j] <- fail.refs[j - 1] + 1
        } else {
          fail.refs[j] <- fail.refs[j - 1]
        }
      }
      n.events <- max(fail.refs)
      event.starts <- by(fail.periods, fail.refs, FUN = min)
      event.ends <- by(fail.periods, fail.refs, FUN = max)
      max.deficits <- vector("numeric", length = n.events)
      for (k in 1:n.events) {
        max.deficits[k] <- max(deficit[event.starts[k]:event.ends[k]])
      }
      
      vulnerability <- mean(max.deficits)
    }
  }
  
  
  
  results <- list( R_policy_M,R_policy,Bellman,S,R_rec,Spill,total_penalty,
                   S_last,R_rec_last,Spill_last,total_penalty_last, rel_ann,rel_time ,rel_vol,
                   resilience,vulnerability )
  
  names(results) <- c("R_policy_M","R_policy","Bellman","Simulation_S",
                      "Simulation_R","Simulation_Spill","Simulation_penalty",
                      "Simulation_S_last",
                      "Simulation_R_last","Simulation_Spill_last","Simulation_penalty_last",
                      "rel_ann","rel_time" ,"rel_vol","resilience","vulnerability")
  return(results)
}


