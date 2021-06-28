

   !=========================================================
      subroutine src2(maxmx,maxmy,meqn,mbc,mx,my,xlower,ylower,dx,dy,q,maux,aux,t,dt)
   !=========================================================
      use geoclaw_module
      use digclaw_module

      implicit none

      !i/o
      double precision :: q(1-mbc:maxmx+mbc,1-mbc:maxmy+mbc, meqn)
      double precision :: aux(1-mbc:maxmx+mbc,1-mbc:maxmy+mbc, maux)
      double precision :: xlower,ylower,dx,dy,t,dt
      integer :: maxmx,maxmy,meqn,mbc,mx,my,maux

      !local
      double precision :: gmod,h,hu,hv,hm,u,v,m,p,phi,kappa,S,rho,tanpsi,dti
      double precision :: D,tau,sigbed,kperm,compress,pm,coeff,tol
      double precision :: zeta,p_hydro,p_litho,p_eq,krate,gamma,dgamma
      double precision :: vnorm,hvnorm,theta,dtheta,w,taucf,fsphi,hvnorm0
      double precision :: shear,sigebar,pmtanh01,rho_fp,seg
      double precision :: b_xx,b_yy,b_xy,chi,beta
      double precision :: slope_xy
      double precision :: t1bot,t2top,beta2,dh,rho2,prat,b_x,b_y,dbdv
      double precision :: vlow,m2,vreg,slopebound
      double precision :: b_eroded,b_remaining,dtcoeff
      integer :: i,j,ii,jj,jjend,icount,curvature
      logical :: ent

      !RPJ
      double precision :: phi1f,phi2f,phi3f,Frf,Fr_starf,betaf,Lambdaf, Lf,Gamf,diamf
      double precision :: mu_df,mu_sf,mu_bf,PIf,mu1f,mu2f,mu3f,viscf


      double precision, allocatable :: moll(:,:)

      ! check for NANs in solution:
      call check4nans(maxmx,maxmy,meqn,mbc,mx,my,q,t,2)

      gmod=grav
      coeff = coeffmanning
      tol = drytolerance !# to prevent divide by zero in gamma
      curvature = 0 !add friction due to curvature acceleration
      !write(*,*) 'src:init,value',p_initialized,init_pmin_ratio
      if (entrainment>0) then
         ent = .true.
      else
         ent = .false.
      endif

      do i=1-mbc+1,mx+mbc-1
         do j=1-mbc+1,my+mbc-1
            theta = 0.d0
            dtheta = 0.d0
            if (bed_normal==1) then
               theta = aux(i,j,i_theta)
               gmod = grav*cos(theta)
               dtheta = -(aux(i+1,j,i_theta) - theta)/dx
            endif

            !call admissibleq(q(i,j,1),q(i,j,2),q(i,j,3),q(i,j,4),q(i,j,5),u,v,m,theta)
            h = q(i,j,1)
            if (h<=drytolerance) cycle
            hu = q(i,j,2)
            hv = q(i,j,3)
            hm = q(i,j,4)
            p =  q(i,j,5)
            phi = aux(i,j,i_phi)
            pm = q(i,j,6)/h
            pm = max(0.0,pm)
            pm = min(1.0,pm)
            fsphi = aux(i,j,i_fsphi)

            jjend = 1
            dti = dt!/real(jjend,kind=8)
            !do jj=1,jjend

            call admissibleq(h,hu,hv,hm,p,u,v,m,theta)
            !integrate momentum source term
            call auxeval(h,u,v,m,p,phi,theta,kappa,S,rho,tanpsi,D,tau,sigbed,kperm,compress,pm)

            !tau = max(tau*(1.0-fsphi),0.0)

            vnorm = sqrt(u**2.0 + v**2.0)
            hvnorm = sqrt(hu**2.0 + hv**2.0)
            hvnorm0 = hvnorm


            !friction from granular material based on h_start and h_stop
            !based on Rocha and Gray, JFM 2019
            !! for now let h_stop be h_start - 10 deg, h_start = h_stop + 2 deg
            ! Other values are for sand

            !degrees
            phi2f = phi
            phi1f = phi2f - fric_offset_val*PIf/180.d0
            phi3f = phi1f + fric_star_val*PIf/180.d0

            b_x = (aux(i+1,j,1)+q(i+1,j,7)-aux(i-1,j,1)-q(i-1,j,7))/(2.d0*dx) ! z/x
            b_y = (aux(i,j+1,1)+q(i,j+1,7)-aux(i,j-1,1)-q(i,j-1,7))/(2.d0*dy) ! z/y

            b_xy = abs(b_x*u/vnorm) + abs(b_y*v/vnorm)
            slope_xy = atan(b_xy)

            PIf = 4.D0*ATAN(1.D0)
            mu1f = tan(phi1f)
            mu2f = tan(phi2f)
            mu3f = tan(phi3f)

            Lambdaf = 1.34d0
            diamf = 0.1
            Lf = 2.d0 * diamf
            betaf = 0.65d0 / sqrt(cos(slope_xy))
            Gamf = 0.77d0 / sqrt(cos(slope_xy))
            Fr_starf = Lambdaf * betaf - Gamf

            !Local Froude number
            Frf = vnorm / sqrt(gmod*h*cos(slope_xy))
            mu_df = mu1f + (mu2f - mu1f) / (1 + h * betaf / (Lf * (Frf + Gamf)))
            if (Frf >= Fr_starf) then ! mu_dynamic
               mu_bf = mu_df
               goto 456
            endif
            mu_sf = mu3f + (mu2f - mu1f) / (1 + h/Lf)
            if (Frf < 1.e-16) then ! mu_static
               mu_bf = mu_sf
               goto 456
            endif

            !mu_intermediate
            mu_bf = (Frf/Fr_starf) * (mu_df - mu_sf) + mu_sf
            goto 456

   456      continue
            ! convert friction coefficient to tau
            ! F = mu N = tau / h
            ! do we assume tau is per unit area or calculate specific for cell?
            !!!tau = gmod * mu_bf * rho_s * h**2.0
            !!!tau = gmod * mu_bf * rho_s * h**2.0 * dx*dy
            !mu = tanphi ?
            !!!tau = sigbed*mu_bf
            !!!tau = sigbed*tan(atan(mu_bf)+atan(tanpsi))
            tau = (m/m_crit)*sigbed*tan(atan(mu_bf)+atan(tanpsi))

            ! viscosity (depth averaged is vh^(1/2)/2)
            viscf = (m/m_crit)*(2*Lf*sqrt(grav)*sin(theta))/(9*betaf*sqrt(cos(theta)))*((mu2f - tan(theta))/(tan(theta)-mu1f))

            !integrate friction
            !!hvnorm = dmax1(0.d0,(hvnorm - dti*tau/rho)*exp(-2.0d0*viscf*dti/(rho_s*h**2.0)))
            hvnorm = dmax1(0.d0,hvnorm - dti*tau/rho)
            hvnorm = hvnorm*exp(-(1.d0-m)*2.0d0*mu*dti/(rho*h**2.0))
            !hvnorm = hvnorm*exp(-(1.d0-m)*2.0d0*0.1*dti/(rho*h**2.0))
            if (hvnorm<1.e-16) hvnorm = 0.0


            if (hvnorm>0.0.and.curvature==1) then
               b_xx=(aux(i+1,j,1)-2.d0*aux(i,j,1)+aux(i-1,j,1))/(dx**2)
               b_yy=(aux(i,j+1,1)-2.d0*aux(i,j,1)+aux(i,j-1,1))/(dy**2)
               b_xy=(aux(i+1,j+1,1)-aux(i-1,j+1,1) -aux(i+1,j-1,1)+aux(i-1,j-1,1))/(4.0*dx*dy)
               chi = (u**2*b_xx + v**2*b_yy + 2.0*u*v*b_xy)/gmod
               chi = max(chi,-1.0)
               taucf = chi*tau
               hvnorm = dmax1(0.d0,hvnorm - dti*taucf/rho)
               taucf = u**2.0*dtheta*tau/gmod
               hvnorm = dmax1(0.d0,hvnorm - dti*taucf/rho)
            endif

            if (hvnorm0>0.0) then
               hu = hvnorm*hu/hvnorm0
               hv = hvnorm*hv/hvnorm0
            endif

            if (p_initialized==0) cycle

            call admissibleq(h,hu,hv,hm,p,u,v,m,theta)
            call auxeval(h,u,v,m,p,phi,theta,kappa,S,rho,tanpsi,D,tau,sigbed,kperm,compress,pm)


            vnorm = sqrt(u**2.0 + v**2.0)

            !integrate shear-induced dilatancy
            sigebar = rho*gmod*h - p + sigma_0
            shear = 2.0*vnorm/h
            krate = 1.5*shear*m*tanpsi/alpha
            sigebar = sigebar*exp(krate*dti)
            !p = rho*gmod*h + sigma_0 - sigebar
            if (compress<1.d15) then !elasticity is = 0.0 but compress is given 1d16 in auxeval
               p = p - dti*3.0*vnorm*tanpsi/(h*compress)
            endif

            !call admissibleq(h,hu,hv,hm,p,u,v,m,theta)
            !call auxeval(h,u,v,m,p,phi,theta,kappa,S,rho,tanpsi,D,tau,sigbed,kperm,compress,pm)
            if (dabs(alpha_seg-1.0)<1.d-6) then
         		seg = 0.0
               rho_fp = rho_f
               pmtanh01=0.0
      		else
         		seg = 1.0
               call calc_pmtanh(pm,seg,pmtanh01)
               rho_fp = max(0.d0,(1.0-pmtanh01))*rho_f
      		endif
            !pmtanh01 = seg*(0.5*(tanh(20.0*(pm-0.80))+1.0))
            !pmtanh01 = seg*(0.5*(tanh(40.0*(pm-0.90))+1.0))

            !integrate pressure relaxation
            !if (compress<1.d15) then !elasticity is = 0.0 but compress is given 1d16 in auxeval
            !   zeta = 3.d0/(compress*h*2.0)  + (rho-rho_fp)*rho_fp*gmod/(4.d0*rho)
            !else
            !   zeta = (rho-rho_fp)*rho_fp*gmod/(4.d0*rho)
            !endif
            zeta = ((m*(sigbed +  sigma_0))/alpha)*3.d0/(h*2.0)  + (rho-rho_fp)*rho_fp*gmod/(4.d0*rho)
            krate=-zeta*2.0*kperm/(h*max(mu,1.d-16))
            p_hydro = h*rho_fp*gmod
            p_litho = (rho_s*m + (1.d0-m)*rho_fp)*gmod*h

            !if (abs(compress*krate)>0.0) then
            !   p_eq = p_hydro + 3.0*vnorm*tanpsi/(compress*h*krate)
            !else
            !   p_eq = p_hydro
            !endif
            !if (abs(pm-.5)>.49) then
            !pmtanh01 = 0.5*(tanh(20.0*(pm-0.80))+1.0)
            p_eq = p_hydro !*(1.0-pmtanh01)
            !p_eq = max(p_eq,0.0)
            !p_eq = min(p_eq,p_litho)

            p = p_eq + (p-p_eq)*exp(krate*dti)


            call admissibleq(h,hu,hv,hm,p,u,v,m,theta)
            call auxeval(h,u,v,m,p,phi,theta,kappa,S,rho,tanpsi,D,tau,sigbed,kperm,compress,pm)


            krate = D*(rho-rho_fp)/rho
            hu = hu*exp(dti*krate/h)
            hv = hv*exp(dti*krate/h)
            hm = hm*exp(-dti*D*rho_fp/(h*rho))
            h = h + krate*dti

            !enddo

            call admissibleq(h,hu,hv,hm,p,u,v,m,theta)
            call auxeval(h,u,v,m,p,phi,theta,kappa,S,rho,tanpsi,D,tau,sigbed,kperm,compress,pm)

            !======================mass entrainment===========================

            vnorm = sqrt(u**2.0 + v**2.0)
            vlow = 0.1d0

            if (ent.and.vnorm.gt.vlow.and.(aux(i,j,i_theta)>0.0)) then
               b_x = (aux(i+1,j,1)+q(i+1,j,7)-aux(i-1,j,1)-q(i-1,j,7))/(2.d0*dx)
               b_y = (aux(i,j+1,1)+q(i,j+1,7)-aux(i,j-1,1)-q(i,j-1,7))/(2.d0*dy)
               dbdv = (u*b_x+v*b_y)/vnorm
               slopebound = 1.e10
               b_eroded = q(i,j,7)
               if (dbdv<slopebound.and.b_eroded<aux(i,j,i_theta)) then
                  b_remaining = aux(i,j,i_theta)-b_eroded
                  m2 = 0.6d0
                  rho2 = m2*2700.d0 + (1.d0-m2)*1000.d0
                  beta2 = 0.66d0
                  t1bot = beta2*vnorm*2.d0*mu*(1.d0-m)/(tanh(h+1.d-2))
                  !write(*,*) '------------'
                  !write(*,*) 'vu',t1bot
                  beta = 1.0-m!tanh(10.d0*m) !tan(1.5*p/(rho*gmod*h))/14.0
                  gamma= rho*beta2*(vnorm**2)*(beta*gmod*coeff**2)/(tanh(h+1.d-2)**(1.0/3.0))
                  !write(*,*) 'gamma', gamma
                  t1bot = t1bot + gamma
                  t1bot = t1bot + tau!+p*tan(phi)
                  !write(*,*) 'tau',tau
                  t2top = min(t1bot,(1.d0-beta*entrainment_rate)*(tau))
                  !write(*,*) 't2top',t2top
                  prat = p/(rho*h)
                  !dh = dti*(t1bot-t2top)/(beta2*tanh(vnorm+1.d-2)*rho2)
                  vreg = ((vnorm-vlow)**2/((vnorm-vlow)**2+1.d0))
                  dtcoeff = entrainment_rate*dti*vreg/(beta2*(vnorm+vlow)*rho2)
                  !dh = dtcoeff*t1bot/(1.d0 + dtcoeff*tan(phi))
                  dh = dtcoeff*(t1bot-t2top)
                  dh = entrainment_rate*dti*(t1bot-t2top)/(rho2*beta2*vnorm)
                  !write(*,*) 'dh',dh
                  !write(*,*) 'dh/dti', dh/dti
                  dh = min(dh,b_remaining)
                  h = h + dh
                  hm = hm + dh*m2
                  q(i,j,7) = q(i,j,7) + dh

                  call admissibleq(h,hu,hv,hm,p,u,v,m,theta)
                  call auxeval(h,u,v,m,p,phi,theta,kappa,S,rho,tanpsi,D,tau,sigbed,kperm,compress,pm)
                  p = prat*rho*h
                  call admissibleq(h,hu,hv,hm,p,u,v,m,theta)
               endif
            endif
            !===================================================================

            q(i,j,1) = h
            q(i,j,2) = hu
            q(i,j,3) = hv
            q(i,j,4) = hm
            q(i,j,5) = p
            q(i,j,6) = pm*h

         enddo
      enddo

      !mollification
      if (.false.) then !mollification ?
      if (.not.allocated(moll)) then
         allocate(moll(mx,my))
      endif
      do i=1,mx
         do j=1,my
         if (q(i,j,1)<=drytolerance) cycle
            p = 0.0
            icount = 0
            do ii=-1,1
               do jj=-1,1
                  !cell weights
                  if ((abs(ii)+abs(jj))==0) then
                     w = 0.5
                  elseif((abs(ii)+abs(jj))==1) then
                     w = 0.3/4.0
                  else
                     w = 0.2/4.0
                  endif
                  if (q(i+ii,j+jj,1)>drytolerance) then
                     p = p + w*q(i+ii,j+jj,5)/q(i+ii,j+jj,1)
                  else
                     p = p + w*q(i,j,5)/q(i,j,1)
                     icount = icount + 1
                  endif
               enddo
            enddo
            moll(i,j) = p !/icount
         enddo
      enddo
      do i=1,mx
         do j=1,my
            if (q(i,j,1)<=drytolerance) cycle
            q(i,j,5) = moll(i,j)*q(i,j,1)
         enddo
      enddo
      if (allocated(moll)) then
         deallocate(moll)
      endif
      endif

      ! Manning friction------------------------------------------------
      if (ifriction==0) return
      if (coeffmanning>0.d0.and.frictiondepth>0.d0) then
         do i=1,mx
            do j=1,my

               if (bed_normal==1) gmod = grav*cos(aux(i,j,i_theta))
               h=q(i,j,1)
               if (h<=frictiondepth) then
                 !# apply friction source term only in shallower water
                  hu=q(i,j,2)
                  hv=q(i,j,3)
                  hm = q(i,j,4)
                  p =  q(i,j,5)
                  phi = aux(i,j,i_phi)
                  theta = aux(i,j,i_theta)
                  call admissibleq(h,hu,hv,hm,p,u,v,m,theta)
                  if (h<tol) cycle
                  pm = q(i,j,6)/h
                  pm = max(0.0,pm)
                  pm = min(1.0,pm)
                  call auxeval(h,u,v,m,p,phi,theta,kappa,S,rho,tanpsi,D,tau,sigbed,kperm,compress,pm)

                  if (h.lt.tol) then
                     q(i,j,2)=0.d0
                     q(i,j,3)=0.d0
                  else
                     beta = 1.0-m !tan(1.5*p/(rho*gmod*h))/14.0
                     gamma= beta*dsqrt(hu**2 + hv**2)*(gmod*coeff**2)/(h**(7.0/3.0))
                     dgamma=1.d0 + dt*gamma
                     q(i,j,2)= q(i,j,2)/dgamma
                     q(i,j,3)= q(i,j,3)/dgamma
                  endif
               endif
            enddo
         enddo
      endif
     ! ----------------------------------------------------------------

      return
      end
