subroutine cal_nlk(time,it,dt1,nlk,uk,work_u,work_vort,work,GlobIntegrals)
  ! ----------------------------------------------------------------------------
  !   VERSION 5 / mars / 2013
  ! - no allocating, all work arrays passed as arguments
  ! - this version 7 real work arrays; I' afraid this is the minimum.
  ! - cofdx..cofdz and poisson are replaced by more elegant loops to minimize
  !   both comput. time and memory consumption.
  !
  ! ----------------------------
  ! This routine computes the RHS of Navier-stokes eqn in fourier space.
  ! ----------------------------------------------------------------------------
  use mpi_header ! Module incapsulates mpif.
  use share_vars
  implicit none

  complex (kind=pr), dimension (ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3),&
       intent (in) :: uk
  complex (kind=pr), dimension (ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3),&
       intent (out):: nlk
  real (kind=pr),intent(inout) :: work(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real (kind=pr), dimension (ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3), &
       intent (inout) :: work_vort, work_u
  real (kind=pr), intent (out) :: dt1
  integer, intent(in) :: it
  real (kind=pr), intent (in) :: time
  real (kind=pr) :: u_max_w
  real (kind=pr) :: t1,t0
  real (kind=pr), dimension (3) :: u_max,u_loc
  integer :: mpicode
  type(Integrals), intent (out) :: GlobIntegrals
  logical :: TimeForDrag

  TimeForDrag=.false.  
  if (modulo(it,itdrag)==0) TimeForDrag=.true. 
  ! is it time for save global quantities?

  ! performance measurement in global variables
  t0=MPI_wtime()
  time_fft2 =0.0 ! time_fft2 is the time spend on ffts during cal_nlk only
  time_ifft2=0.0 ! time_ifft2 is the time spend on iffts during cal_nlk only


  !-----------------------------------------------
  !-- Calculate ux and uy in physical space
  !-----------------------------------------------
  t1=MPI_wtime()
  call cofitxyz (uk(:,:,:,1), work_u(:,:,:,1))
  call cofitxyz (uk(:,:,:,2), work_u(:,:,:,2))
  call cofitxyz (uk(:,:,:,3), work_u(:,:,:,3))
  time_u=time_u + MPI_wtime() - t1

  !------------------------------------------------
  ! TEMP::: compute divergence
  !-----------------------------------------------
  if (TimeForDrag) then
!     call compute_divergence(FIXME)
  endif

  !-----------------------------------------------
  !-- Compute vorticity
  !-----------------------------------------------
  t1=MPI_wtime()
  call compute_vorticity(work_vort,nlk,uk)
  time_vor=time_vor + MPI_wtime() - t1

  !-----------------------------------------------
  !-- Compute kinetic energy and dissipation rate + mask volume
  !-----------------------------------------------  
  if((TimeForDrag) .and. (iKinDiss==1)) then
     call Energy_Dissipation ( GlobIntegrals, work_u, work_vort )
  endif

  !-------------------------------------------------------------
  !-- Calculate omega x u (cross-product)
  !-- add penalization term
  !-- and transform the result into Fourier space 
  !-------------------------------------------------------------
  t1=MPI_wtime()
  if (iPenalization==1) then
     call omegacrossu_penalize(nlk,work,work_u,work_vort,TimeForDrag,&
          GlobIntegrals)
  else ! no penalization
     call omegacrossu_nopen(nlk,work,work_u,work_vort)
  endif
  time_curl=time_curl + MPI_wtime() - t1

  !-------------------------------------------------------------
  ! add pressure, new version
  ! p=(i*kx*sxk + i*ky*syk + i*kz*szk) / k**2
  ! note: we use rotational formulation: p is NOT the physical pressure
  !------------------------------------------------------------- 
  t1=MPI_wtime()
  call add_grad_pressure(nlk)
  time_p=time_p + MPI_wtime() - t1

  !-------------------------------------------------------------
  !-- Calculate maximum velocity + TIME STEP
  !-------------------------------------------------------------
  u_loc(1)=maxval(abs(work_u(:,:,:,1)))  ! local maximum of x-velocity magnitude
  u_loc(2)=maxval(abs(work_u(:,:,:,2)))  ! local maximum of y-velocity magnitude
  u_loc(3)=maxval(abs(work_u(:,:,:,3)))  ! local maximum of z-velocity magnitude

  ! max at 0th process
  call MPI_REDUCE(u_loc,u_max,3,mpireal,MPI_MAX,0,MPI_COMM_WORLD,mpicode)

  !--Adjust time step at 0th process
  if ( mpirank == 0 ) then
     !--------
     ! CFL
     !--------
     u_max_w=max ( u_max(1)/dx, u_max(2)/dy, u_max(3)/dz )
     if (abs(u_max_w) >= 1.0d-8) then
        dt1=cfl / u_max_w        
     else
        dt1=1.0d-2
     endif
     !--------
     ! fixed time step?
     !--------
     if (dt_fixed>0.0) then
        dt1=min(dt_fixed, dt1)
     endif
     !--------
     ! round it to save cal_vis
     !--------
     call truncate(dt1,dt1) 
     ! round time step to one digit: 
     ! saves time because no need to recompute cal_vis
     !--------
     ! stability for penalty term: 
     ! do it after truncating to get the largest posisble value, 
     ! which will be constant anyways
     !--------
     if (iPenalization > 0) dt1=min(0.99*eps,dt1) 
     ! time step is smaller than eps 
  endif

  !-- Broadcast time step to all processes
  call MPI_BCAST(dt1,1,mpireal,0,MPI_COMM_WORLD,mpicode)

  time_nlk_fft=time_nlk_fft + time_fft2 + time_ifft2
  time_nlk=time_nlk + MPI_wtime() - t0
end subroutine cal_nlk


! we outsource the actual penalization (even though its a fairly
! simple process) to remove some lines in the actual cal_nlk also, at
! this occasion, we directly compute the integral hydrodynamic forces,
! if its time to do so.
subroutine Penalize(work,work_u,iDir,TimeForDrag,GlobIntegrals )    
  use share_vars
  implicit none
  integer, intent (in) :: iDir
  logical, intent (in) :: TimeForDrag
  real (kind=pr), dimension (ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)),&
       intent (out) :: work
  real (kind=pr), dimension (ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3),&
       intent (in) :: work_u
  type(Integrals), intent (out) :: GlobIntegrals

  ! compute penalization term
  if (iMoving == 1) then
     work=-mask*(work_u(:,:,:,iDir) - us(:,:,:,iDir))  
  else
     work=-mask*(work_u(:,:,:,iDir))
  endif

  ! if its time, compute drag forces
  if ((TimeForDrag).and.(iDrag==1)) then
     call IntegralForce ( GlobIntegrals, work, iDir ) 
  endif
end subroutine Penalize

!------------------------------------------------------------------------------

subroutine truncate(a,b)
  ! rounds time step (from 1.246262e-2 to 1.2e-2)
  use share_vars
  implicit none
  real(kind=pr) :: a,b
  character (len=7) :: str
  write (str,'(es7.1)') a
  read (str,*) b
end subroutine truncate


subroutine IntegralForce ( GlobIntegrals, work, iDirection ) 
  use share_vars
  use mpi_header
  implicit none
  real (kind=pr), dimension (ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)),&
       intent (inout) :: work
  type(Integrals), intent (out) :: GlobIntegrals
  integer, intent (in) :: iDirection
  integer :: mpicode
  real (kind=pr) :: Force_local

  Force_local =dx*dy*dz*sum( work )  
  call MPI_REDUCE (Force_local,GlobIntegrals%Force(iDirection),1,mpireal,&
       MPI_SUM,0,MPI_COMM_WORLD,mpicode)  ! max at 0th process  
end subroutine IntegralForce


! Compute the kinetic energy, dissipation rate and mask volume.  Store
! all these in the structure GlobIntegrals (definition see
! share_vars).
subroutine Energy_Dissipation ( GlobIntegrals, u, vort )
  use share_vars
  use mpi_header
  implicit none

  real (kind=pr), dimension (ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3),&
       intent (in) :: vort, u
  type(Integrals), intent (out) :: GlobIntegrals
  real (kind=pr) :: E_kin_local, Dissip_local, Volume_local
  integer :: mpicode

  E_kin_local =0.5d0*dx*dy*dz*sum( u*u )
  Dissip_local=-nu*dx*dy*dz*sum( vort*vort )

  if (iPenalization==1) then
     Volume_local=dx*dy*dz*sum( mask )*eps
  else
     Volume_local=0.d0
  endif

  call MPI_REDUCE(E_kin_local,GlobIntegrals%E_kin,1,mpireal,MPI_SUM,0,&
       MPI_COMM_WORLD,mpicode)  ! sum at 0th process
  call MPI_REDUCE(Dissip_local,GlobIntegrals%Dissip,1,mpireal,MPI_SUM,&
       0,MPI_COMM_WORLD,mpicode)  ! sum at 0th process
  call MPI_REDUCE(Volume_local,GlobIntegrals%Volume,1,mpireal,MPI_SUM,&
       0,MPI_COMM_WORLD,mpicode)  ! sum at 0th process
end subroutine Energy_Dissipation


! Compute the pressure, 
! p=(i*kx*sxk + i*ky*syk + i*kz*szk) / k**2 
! note: we use rotational formulation: p is NOT the physical pressure
subroutine compute_pressure(pk,nlk)
  use mpi_header
  use share_vars
  implicit none

  integer :: ix,iy,iz
  real(kind=pr) :: kx,ky,kz,k2
  complex(kind=pr),intent(out):: pk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3))
  complex(kind=pr),intent(out):: nlk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3)

  do iy=ca(3),cb(3)  ! ky : 0..ny/2-1 ,then, -ny/2..-1
     ky=scaley*dble(modulo(iy+ny/2,ny)-ny/2)
     do ix=ca(2),cb(2) ! kx : 0..nx/2
        kx=scalex*dble(ix)
        do iz=ca(1),cb(1) ! kz : 0..nz/2-1 ,then, -nz/2..-1
           kz=scalez*dble(modulo(iz+nz/2,nz)-nz/2)
           k2=kx*kx+ky*ky+kz*kz
           if(k2 .ne. 0.0) then
              ! contains the pressure in Fourier space
              pk(iz,ix,iy)=&
                   (kx*nlk(iz,ix,iy,1)&
                   +ky*nlk(iz,ix,iy,2)&
                   +kz*nlk(iz,ix,iy,3)&
                   )/k2
           endif
        enddo
     enddo
  enddo
end subroutine compute_pressure


! Add the gradient of the pressure to the nonlinear term.
subroutine add_grad_pressure(nlk)
  use mpi_header
  use share_vars
  implicit none

  integer :: ix,iy,iz
  real(kind=pr) :: kx,ky,kz,k2
  complex (kind=pr) :: qk
  complex(kind=pr),intent(inout):: nlk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3)

  do iy=ca(3),cb(3) ! ky : 0..ny/2-1 ,then, -ny/2..-1     
     ky=scaley*dble(modulo(iy+ny/2,ny)-ny/2)     
     do ix=ca(2),cb(2) ! kx : 0..nx/2
        kx=scalex*dble(ix)
        do iz=ca(1),cb(1) ! kz : 0..nz/2-1 ,then, -nz/2..-1         
           kz=scalez*dble(modulo(iz+nz/2,nz)-nz/2)
           k2=kx*kx+ky*ky+kz*kz
           if (k2 .ne. 0.0) then  
              qk=(kx*nlk(iz,ix,iy,1)&
                   +ky*nlk(iz,ix,iy,2)&
                   +kz*nlk(iz,ix,iy,3)&
                   )/k2
              nlk(iz,ix,iy,1)=nlk(iz,ix,iy,1) - kx*qk  
              nlk(iz,ix,iy,2)=nlk(iz,ix,iy,2) - ky*qk
              nlk(iz,ix,iy,3)=nlk(iz,ix,iy,3) - kz*qk
           endif
        enddo
     enddo
  enddo
end subroutine add_grad_pressure


!FIXME: temp code, removed from main cal_nlk
subroutine compute_divergence()
  use mpi_header
  use share_vars
  implicit none
!!$  
!!$  ! compute max val of {|div(.)|/|.|} over entire domain
!!$  do iz=ca(1),cb(1)
!!$     kz=scalez*(modulo(iz+nz/2,nz) -nz/2)
!!$     do iy=ca(3),cb(3)
!!$        ky=scaley*(modulo(iy+ny/2,ny) -ny/2)
!!$        do ix=ca(2),cb(2)
!!$           kx=scalex*ix
!!$           ! divergence of velocity field
!!$           nlk(iz,ix,iy,1)=dcmplx(0.d0,1.d0)*(kx*uk(iz,ix,iy,1)+ky*uk(iz,ix,iy,2)+kz*uk(iz,ix,iy,3))
!!$        enddo
!!$     enddo
!!$  enddo
!!$  ! now nlk(:,:,:,1) contains divergence field
!!$  call cofitxyz(nlk(:,:,:,1),work)
!!$  call MPI_REDUCE (maxval(work), GlobIntegrals%Divergence, 1, mpireal, &
!!$       MPI_MAX, 0, MPI_COMM_WORLD, mpicode)  ! max at 0th process  
!!$
!!$  call Energy_Dissipation ( GlobIntegrals, work_u, work_vort )
!!$
!!$  if (mpirank ==0) then
!!$     write (*,'("max{div(u)}=",es15.8,"max{div(u)}/||u||=",es15.8)') &
!!$          GlobIntegrals%Divergence, GlobIntegrals%Divergence/(2.d0*GlobIntegrals%E_kin)
!!$  endif
end subroutine compute_divergence


! Compute omega cross u with penalization and imoving=1
subroutine omegacrossu_pen_moving(nlk,work,u,vort)
  use mpi_header
  use share_vars
  implicit none

  real(kind=pr),intent(inout) :: work(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  complex(kind=pr),intent(out):: nlk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3)
  real(kind=pr),intent(inout) :: u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3)
  real(kind=pr),intent(inout) :: vort(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3)

  work=u(:,:,:,2)*vort(:,:,:,3) -u(:,:,:,3)*vort(:,:,:,2)&
       -(u(:,:,:,1)-us(:,:,:,1))*mask
  call coftxyz(work,nlk(:,:,:,1))
  work=u(:,:,:,3)*vort(:,:,:,1) -u(:,:,:,1)*vort(:,:,:,3)&
       -(u(:,:,:,2)-us(:,:,:,2))*mask
  call coftxyz(work,nlk(:,:,:,2))
  work=u(:,:,:,1)*vort(:,:,:,2) -u(:,:,:,2)*vort(:,:,:,1)&
       -(u(:,:,:,3)-us(:,:,:,3))*mask
  call coftxyz(work,nlk(:,:,:,3))
endsubroutine omegacrossu_pen_moving


! Compute omega cross u in the case of no penalization
subroutine omegacrossu_nopen(nlk,work,u,vort)
  use mpi_header
  use share_vars
  implicit none

  real(kind=pr),intent(inout) :: work(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  complex(kind=pr),intent(out):: nlk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3)
  real(kind=pr),intent(inout) :: u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3)
  real(kind=pr),intent(inout) :: vort(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3)
  
  work=u(:,:,:,2)*vort(:,:,:,3) - u(:,:,:,3)*vort(:,:,:,2)
  call coftxyz(work,nlk(:,:,:,1))
  work=u(:,:,:,3)*vort(:,:,:,1) - u(:,:,:,1)*vort(:,:,:,3)
  call coftxyz(work,nlk(:,:,:,2))
  work=u(:,:,:,1)*vort(:,:,:,2) - u(:,:,:,2)*vort(:,:,:,1)
  call coftxyz(work,nlk(:,:,:,3))
endsubroutine omegacrossu_nopen


! Compute omega cross u with penalization and imoving=0
subroutine omegacrossu_pen_nomove(nlk,work,u,vort)
  use mpi_header
  use share_vars
  implicit none

  real(kind=pr),intent(inout) :: work(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  complex(kind=pr),intent(out):: nlk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3)
  real(kind=pr),intent(inout) :: u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3)
  real(kind=pr),intent(inout) :: vort(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3)
  
  work=u(:,:,:,2)*vort(:,:,:,3)&
       -u(:,:,:,3)*vort(:,:,:,2)&
       -u(:,:,:,1)*mask
  call coftxyz(work,nlk(:,:,:,1))
  work=u(:,:,:,3)*vort(:,:,:,1)&
       -u(:,:,:,1)*vort(:,:,:,3)&
       -u(:,:,:,2)*mask
  call coftxyz(work,nlk(:,:,:,2))
  work=u(:,:,:,1)*vort(:,:,:,2)&
       -u(:,:,:,2)*vort(:,:,:,1)&
       -u(:,:,:,3)*mask
  call coftxyz(work,nlk(:,:,:,3))
end subroutine omegacrossu_pen_nomove


! Compute omega cross u with penalization 
subroutine omegacrossu_penalize(nlk,work,u,vort,TimeForDrag,GlobIntegrals)
  use mpi_header
  use share_vars
  implicit none

  real(kind=pr),intent(inout) :: work(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  complex(kind=pr),intent(out):: nlk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3)
  real(kind=pr),intent(inout) :: u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3)
  real(kind=pr),intent(inout) :: vort(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3)
  logical,intent(in) :: TimeForDrag
  type(Integrals), intent (inout) :: GlobIntegrals
  
  ! x component
  call Penalize ( work, u, 1, TimeForDrag, GlobIntegrals )
  work=u(:,:,:,2)*vort(:,:,:,3)&
       - u(:,:,:,3)*vort(:,:,:,2) + work
  call coftxyz (work, nlk(:,:,:,1))
  ! y component
  call Penalize ( work, u, 2, TimeForDrag, GlobIntegrals )
  work=u(:,:,:,3)*vort(:,:,:,1)&
       - u(:,:,:,1)*vort(:,:,:,3) + work
  call coftxyz (work, nlk(:,:,:,2))
  ! z component
  call Penalize ( work, u, 3, TimeForDrag, GlobIntegrals )
  work=u(:,:,:,1)*vort(:,:,:,2)&
       - u(:,:,:,2)*vort(:,:,:,1) + work
  call coftxyz (work, nlk(:,:,:,3))     
end subroutine omegacrossu_penalize
