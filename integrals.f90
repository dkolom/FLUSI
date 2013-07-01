! Wrapper for writing integral quantities to file
subroutine write_integrals(time,uk,u,vort,nlk,work)
  use mpi_header
  use vars
  implicit none

  complex (kind=pr),intent(inout)::uk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nd)
  real (kind=pr),intent(inout) :: u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:nd)
  real (kind=pr),intent(inout) :: vort(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:nd)
  complex(kind=pr),intent(inout) ::nlk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nd)
  real(kind=pr),intent(inout):: work(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr), intent(in) :: time

  select case(method(1:3))
  case("fsi")
     call write_integrals_fsi(time,uk,u,vort,nlk,work)
  case("mhd")
     call write_integrals_mhd(time,uk,u,vort,nlk,work)
  case default
     if (mpirank == 0) write(*,*) "Error! Unkonwn method in write_integrals"
     call abort
  end select
end subroutine write_integrals


! fsi version of writing integral quantities to disk
subroutine write_integrals_fsi(time,uk,u,vort,nlk,work)
  use mpi_header
  use fsi_vars
  implicit none

  complex(kind=pr),intent(inout)::uk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nd)
  complex(kind=pr),intent(inout) ::nlk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nd)
  real(kind=pr),intent(inout) :: u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:nd)
  real(kind=pr),intent(inout) :: vort(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:nd)
  real(kind=pr),intent(inout):: work(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr), intent(in) :: time
  
  ! FIXME: compute integral quantities

  ! NB: consider using subroutines (eg: compute_max_div,
  ! compute_energies, etc): see mhd version.

  if(mpirank == 0) then
     ! FIXME: see mhd integrals for an output format using tabs and
     ! avoiding the empty space at the start of the line.
     open(14,file='drag_data',status='unknown',position='append')
     write(14,'(7(es12.4,1x))')  time,GlobalIntegrals%Ekin,&
          GlobalIntegrals%Dissip, GlobalIntegrals%Force(1),&
          GlobalIntegrals%Force(2),GlobalIntegrals%Force(3),&
       GlobalIntegrals%Volume
     close(14)
  endif
end subroutine write_integrals_fsi


! The mhd version of writing integral quantities to disk.
! In order to make the asy files useful for both hd and mhd codes,
! please output velocity and magnetic fields quantities in separate
! files, or (if there aren't too many columns) put all the
! velocity-only quantities first.
subroutine write_integrals_mhd(time,ubk,ub,wj,nlk,work)
  use mpi_header
  use mhd_vars
  implicit none

  complex (kind=pr),intent(inout)::ubk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nd)
  real (kind=pr),intent(inout) :: ub(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:nd)
  real (kind=pr),intent(inout) :: wj(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:nd)
  complex(kind=pr),intent(inout) ::nlk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nd)
  real(kind=pr),intent(inout):: work(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr), intent(in) :: time
  integer :: i
  ! Local loop variables
  real(kind=pr) :: Ekin,Ekinx,Ekiny,Ekinz
  real(kind=pr) :: Emag,Emagx,Emagy,Emagz
  real(kind=pr) :: meanjx,meanjy,meanjz
  real(kind=pr) :: jmax,jxmax,jymax,jzmax
  real(kind=pr) :: divu,divb
  real(kind=pr) :: dissu,dissb
  real(kind=pr) :: fluid_volume

  !!! Make sure that we have the fields that we need in the space we need:

  ! Compute u and B to physical space
  do i=1,nd
     call ifft(ub(:,:,:,i),ubk(:,:,:,i))
  enddo
  
  ! Compute the vorticity and store the result in the first three 3D
  ! arrays of nlk.
  call curl(nlk(:,:,:,1),nlk(:,:,:,2),nlk(:,:,:,3),&
       ubk(:,:,:,1),ubk(:,:,:,2),ubk(:,:,:,3))

  ! Compute the current density and store the result in the last three
  ! 3D arrays of nlk.
  call curl(nlk(:,:,:,4),nlk(:,:,:,5),nlk(:,:,:,6),&
       ubk(:,:,:,4),ubk(:,:,:,5),ubk(:,:,:,6))

  ! Transform vorcitity and current density to physical space, store
  ! in wj
  do i=1,nd
     call ifft(wj(:,:,:,i),nlk(:,:,:,i))
  enddo

  !!! Compute the integral quantities and output to disk:

  ! Compute the fluid volume.
  call compute_fluid_volume(fluid_volume)

  ! Compute kinetic energies.
  call compute_energies(Ekin,Ekinx,Ekiny,Ekinz,&
       ub(:,:,:,1),ub(:,:,:,2),ub(:,:,:,3))
  if(mpirank == 0) then
     open(14,file='ekvt',status='unknown',position='append')
     ! 9 outputs, including tabs
     write(14,'(e12.6,A,e12.6,A,e12.6,A,e12.6,A,e12.6)') &
          time,tab,Ekin,tab,Ekinx,tab,Ekiny,tab,Ekinz
     close(14)
  endif

  ! Comptue magnetic energies.
  call compute_energies(Emag,Emagx,Emagy,Emagz,&
       ub(:,:,:,4),ub(:,:,:,5),ub(:,:,:,6))
  if(mpirank == 0) then
     open(14,file='ebvt',status='unknown',position='append')
     ! 9 outputs, including tabs
     write(14,'(e12.6,A,e12.6,A,e12.6,A,e12.6,A,e12.6)') &
          time,tab,Emag,tab,Emagx,tab,Emagy,tab,Emagz
     close(14)
  endif

  ! Compute current density values.
  call compute_components(meanjx,meanjy,meanjz,&
       wj(:,:,:,4),wj(:,:,:,5),wj(:,:,:,6))
  call compute_max(jmax,jxmax,jymax,jzmax,wj(:,:,:,4),wj(:,:,:,5),wj(:,:,:,6))
  if(mpirank == 0) then
     open(14,file='jvt',status='unknown',position='append')
     ! 15 outputs, including tabs
     write(14,&
          '(e12.6,A,e12.6,A,e12.6,A,e12.6,A,e12.6,A,e12.6,A,e12.6,A,e12.6)')&
          time,tab,meanjx,tab,meanjy,tab,meanjz,tab,jmax,tab,jxmax,tab,&
          jymax,tab,jzmax
     close(14)
  endif
  
  ! Compute kinetic and magnetic energy dissipation
  ! Kinetic energy dissipation is nu*< |vorticity| >
  call compute_mean_norm(dissu,wj(:,:,:,1),wj(:,:,:,2),wj(:,:,:,3))
  dissu=nu*dissu
  ! Magnetic energy dissipation is eta*< |current density| >
  call compute_mean_norm(dissb,wj(:,:,:,4),wj(:,:,:,5),wj(:,:,:,6))
  dissb=eta*dissb
  if(mpirank == 0) then
     open(14,file='dissvt',status='unknown',position='append')
     ! 3 outputs
     write(14,'(e12.6,A,e12.6,A,e12.6)') time,tab,dissu,tab,dissb
     close(14)
  endif

  ! Compute max divergence.
  call compute_max_div(divu,&
       ubk(:,:,:,1),ubk(:,:,:,2),ubk(:,:,:,3),&
       ub(:,:,:,1),ub(:,:,:,2),ub(:,:,:,3),&
       work,nlk(:,:,:,1))
  call compute_max_div(divb,&
       ubk(:,:,:,4),ubk(:,:,:,5),ubk(:,:,:,6),&
       ub(:,:,:,4),ub(:,:,:,5),ub(:,:,:,6),&
       work,nlk(:,:,:,1))
  if(mpirank == 0) then
     open(14,file='dvt',status='unknown',position='append')
     ! 3 outputs
     write(14,'(e12.6,A,e12.6,A,e12.6)') time,tab,divu,tab,divb
     close(14)
  endif
end subroutine write_integrals_mhd


! Compute the average total energy and energy in each direction for a
! physical-space vector fields with components f1, f2, f3, leaving the
! input vector field untouched.
subroutine compute_energies(E,Ex,Ey,Ez,f1,f2,f3)
  use mpi_header
  use vars
  implicit none
  
  real(kind=pr),intent(out) :: E,Ex,Ey,Ez
  real(kind=pr),intent(inout):: f1(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),intent(inout):: f2(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),intent(inout):: f3(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr) :: LE,LEx,LEy,LEz ! local quantities
  real(kind=pr) :: v1,v2,v3
  integer :: ix,iy,iz,mpicode

  ! initialize local variables
  LE=0.d0
  LEx=0.d0
  LEy=0.d0
  LEz=0.d0

  ! Add contributions in physical space
  do ix=ra(1),rb(1)
     do iy=ra(2),rb(2)
        do iz=ra(3),rb(3)
           v1=f1(ix,iy,iz)
           v2=f2(ix,iy,iz)
           v3=f3(ix,iy,iz)
           
           LE=Le + v1*v1 + v2*v2 + v3*v3
           LEx=LEx + v1*v1
           LEy=LEy + v2*v2
           LEz=LEz + v3*v3
        enddo
     enddo
  enddo

  LE=LE*dx*dy*dz
  LEx=LEx*dx*dy*dz
  LEy=LEy*dx*dy*dz
  LEz=LEz*dx*dy*dz

  ! Sum over all MPI processes
  call MPI_REDUCE(LE,E,&
       1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
       MPI_COMM_WORLD,mpicode)
  call MPI_REDUCE(LEx,Ex,&
       1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
       MPI_COMM_WORLD,mpicode)
  call MPI_REDUCE(LEy,Ey,&
       1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
       MPI_COMM_WORLD,mpicode)
  call MPI_REDUCE(LEz,Ez,&
       1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
       MPI_COMM_WORLD,mpicode)
end subroutine compute_energies


! Compute the average average component in each direction for a
! physical-space vector fields with components f1, f2, f3, leaving the
! input vector field untouched.
subroutine compute_components(Cx,Cy,Cz,f1,f2,f3)
  use mpi_header
  use vars
  implicit none
  
  real(kind=pr),intent(out) :: Cx,Cy,Cz
  real(kind=pr),intent(inout):: f1(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),intent(inout):: f2(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),intent(inout):: f3(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr) :: LCx,LCy,LCz ! local quantities
  real(kind=pr) :: v1,v2,v3
  integer :: ix,iy,iz,mpicode

  ! initialize local variables
  LCx=0.d0
  LCy=0.d0
  LCz=0.d0

  ! Add contributions in physical space
  do ix=ra(1),rb(1)
     do iy=ra(2),rb(2)
        do iz=ra(3),rb(3)
           v1=f1(ix,iy,iz)
           v2=f2(ix,iy,iz)
           v3=f3(ix,iy,iz)
           
           LCx=LCx + v1
           LCy=LCy + v2
           LCz=LCz + v3
        enddo
     enddo
  enddo

  LCx=LCx*dx*dy*dz
  LCy=LCy*dx*dy*dz
  LCz=LCz*dx*dy*dz
  
  ! Sum over all MPI processes
  call MPI_REDUCE(LCx,Cx,&
       1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
       MPI_COMM_WORLD,mpicode)
  call MPI_REDUCE(LCy,Cy,&
       1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
       MPI_COMM_WORLD,mpicode)
  call MPI_REDUCE(LCz,Cz,&
       1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
       MPI_COMM_WORLD,mpicode)
end subroutine compute_components


! Compute the maximum non-normalized divergence of the given 3D field
! fk1, fk2, fk3, 
subroutine compute_max_div(maxdiv,fk1,fk2,fk3,f1,f2,f3,div,divk)
  use mpi_header
  use vars
  implicit none

  real(kind=pr),intent(out) :: maxdiv  
  real(kind=pr),intent(in):: f1(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),intent(in):: f2(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),intent(in):: f3(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  complex(kind=pr),intent(in) ::fk1(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3))
  complex(kind=pr),intent(in) ::fk2(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3))
  complex(kind=pr),intent(in) ::fk3(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3))
  complex(kind=pr),intent(inout) ::divk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3))
  real(kind=pr),intent(inout):: div(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  integer :: ix,iy,iz,mpicode
  real(kind=pr) :: kx, ky, kz, locmax,  v1,v2,v3,d
  ! real(kind=pr) fnorm ! Only used for normalized version.
  complex(kind=pr) :: imag ! imaginary unit

  imag = dcmplx(0.d0,1.d0)

  ! Compute the divergence in Fourier space, store in divk
  do iz=ca(1),cb(1)
     kz=scalez*(modulo(iz+nz/2,nz) -nz/2)
     do ix=ca(2),cb(2)
        kx=scalex*ix
        do iy=ca(3),cb(3)
           ky=scaley*(modulo(iy+ny/2,ny) -ny/2)
           divk(iz,ix,iy)=imag*&
                (kx*fk1(iz,ix,iy)&
                +ky*fk2(iz,ix,iy)&
                +kz*fk3(iz,ix,iy))
        enddo
     enddo
  enddo

  call ifft(div,divk)
  
  ! Find the local max
  locmax=0.d0
  do ix=ra(1),rb(1)
     do iy=ra(2),rb(2)
        do iz=ra(3),rb(3)
           v1=f1(ix,iy,iz)
           v2=f2(ix,iy,iz)
           v3=f3(ix,iy,iz)
           
           ! Normalized version:
           ! fnorm=v1*v2 + v2*v2 + v3*v3 + 1d-8 ! avoid division by zero
           ! d=abs(div(ix,iy,iz))/fnorm

           ! Non-normalized version:
           d=abs(div(ix,iy,iz))

           if(d > locmax) then
              locmax=d
           endif
        enddo
     enddo
  enddo

  ! Find the global max
  call MPI_REDUCE(locmax,maxdiv,&
       1,MPI_DOUBLE_PRECISION,MPI_MAX,0,&
       MPI_COMM_WORLD,mpicode)
end subroutine compute_max_div


! Compute the maximum components of the given 3D field with
! componennts f1, f2, f3.
subroutine compute_max(vmax,xmax,ymax,zmax,f1,f2,f3)
  use mpi_header
  use vars
  implicit none

  real(kind=pr),intent(out) :: vmax,xmax,ymax,zmax
  real(kind=pr),intent(in):: f1(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),intent(in):: f2(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),intent(in):: f3(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  integer :: ix,iy,iz,mpicode
  real(kind=pr) :: v1,v2,v3
  real(kind=pr) :: Lmax,Lxmax,Lymax,Lzmax

  Lmax=0.d0
  Lxmax=0.d0
  Lymax=0.d0
  Lzmax=0.d0

  ! Find the (per-process) max norm and max components in physical
  ! space
  do ix=ra(1),rb(1)
     do iy=ra(2),rb(2)
        do iz=ra(3),rb(3)
           v1=f1(ix,iy,iz)
           v2=f2(ix,iy,iz)
           v3=f3(ix,iy,iz)
           Lmax=max(Lmax,dsqrt(v1*v1 + v2*v2 + v3*v3))
           Lxmax=max(Lxmax,v1)
           Lymax=max(Lymax,v2)
           Lzmax=max(Lzmax,v3)
        enddo
     enddo
  enddo

  ! Determine the global max
  call MPI_REDUCE(Lmax,vmax,&
       1,MPI_DOUBLE_PRECISION,MPI_MAX,0,&
       MPI_COMM_WORLD,mpicode)
  call MPI_REDUCE(Lxmax,xmax,&
       1,MPI_DOUBLE_PRECISION,MPI_MAX,0,&
       MPI_COMM_WORLD,mpicode)
  call MPI_REDUCE(Lymax,ymax,&
       1,MPI_DOUBLE_PRECISION,MPI_MAX,0,&
       MPI_COMM_WORLD,mpicode)
  call MPI_REDUCE(Lzmax,zmax,&
       1,MPI_DOUBLE_PRECISION,MPI_MAX,0,&
       MPI_COMM_WORLD,mpicode)
end subroutine compute_max


! Compute the meannorm of the given field with x-space components f1, f2, f3.
subroutine compute_mean_norm(mean,f1,f2,f3)
  use mpi_header
  use vars
  implicit none

  real(kind=pr),intent(out) :: mean
  real(kind=pr),intent(in):: f1(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),intent(in):: f2(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),intent(in):: f3(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  integer :: ix,iy,iz,mpicode
  real(kind=pr) :: v1,v2,v3
  real(kind=pr) :: Lmean ! Process-local mean

  Lmean=0.d0
  
  do ix=ra(1),rb(1)
     do iy=ra(2),rb(2)
        do iz=ra(3),rb(3)
           v1=f1(ix,iy,iz)
           v2=f2(ix,iy,iz)
           v3=f3(ix,iy,iz)
           
           Lmean=Lmean + v1*v1 + v2*v2 + v3*v3
        enddo
     enddo
  enddo
  
  Lmean=Lmean*dx*dy*dz
  
  call MPI_REDUCE(Lmean,mean,&
       1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
       MPI_COMM_WORLD,mpicode)
end subroutine compute_mean_norm


! Compute the fluid volume.
! NB: mask is a global!
subroutine compute_fluid_volume(volume)
  use mpi_header
  use vars
  implicit none

  real(kind=pr),intent(out) :: volume
  integer :: ix,iy,iz,mpicode
  real(kind=pr) :: Lvolume ! Process-local volume

  if(iPenalization == 0) then
     volume=xl*yl*zl
  else
     Lvolume=0.d0
     
     if (mpirank == 0) then
        write(*,*) "FIXME: please write the code for finding the volume with penalization.  Thanks a bunch, eh!"
     endif
     call abort
     
     do ix=ra(1),rb(1)
        do iy=ra(2),rb(2)
           do iz=ra(3),rb(3)
              ! FIXME: compute stuff using the mask, eh?
           enddo
        enddo
     enddo
     
     Lvolume=Lvolume*dx*dy*dz ! Probably necessary?
     
     call MPI_REDUCE(Lvolume,volume,&
          1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
          MPI_COMM_WORLD,mpicode)
  endif
end subroutine compute_fluid_volume