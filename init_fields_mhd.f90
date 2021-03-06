! Initialize fields for mhd simulations
subroutine init_fields_mhd(n1,time,it,dt0,dt1,ubk,nlk,wj,explin)
  use mpi_header
  use fsi_vars
  implicit none

  integer,intent (inout) :: n1,it
  real (kind=pr),intent (inout) :: time,dt1,dt0
  complex (kind=pr),intent (out):: ubk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nd)
  complex (kind=pr),intent (out)::&
       nlk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nd,0:1)
  real(kind=pr),intent (inout) :: wj(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:nd)
  real (kind=pr),intent(inout)::explin(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nf)
  integer :: i
  
  ! Assign zero values
  time=0.0d0
  dt1=0.0d0
  ubk=dcmplx(0.0d0,0.0d0)
  nlk=dcmplx(0.0d0,0.0d0)
  explin=0.0
  it=0
  wj=0.0d0

  select case(inicond)
  case("quiescent")
     ubk=dcmplx(0.0d0,0.0d0)
  case("constant")
     call init_const(ubk,wj)
  case("orszagtang")
     call init_orszagtang(ubk,wj)
  case("smc")
     call init_smc(ubk,wj)
  case("TaylorCouette")
     call init_tc_mhd(ubk,wj)
  case("infile")
     ! read in fluid velocity from files
     call Read_Single_File ( file_ux, wj(:,:,:,1) )
     call Read_Single_File ( file_uy, wj(:,:,:,2) )
     call Read_Single_File ( file_uz, wj(:,:,:,3) )
    
     ! read in b-field from files
     call Read_Single_File ( file_bx, wj(:,:,:,4) )
     call Read_Single_File ( file_by, wj(:,:,:,5) )
     call Read_Single_File ( file_bz, wj(:,:,:,6) )
     
     ! transform everything to fourier space
     do i = 1,6
      call fft( ubk(:,:,:,i), wj(:,:,:,i) )
     enddo
     
  case default
     if(inicond(1:8) == "backup::") then
        call Read_Runtime_Backup(inicond(9:len(inicond)),&
             time,dt0,dt1,n1,it,ubk,nlk,explin,wj(:,:,:,1))
     else
        if (mpirank==0) then
           write (*,*) inicond
           write (*,*) '??? ERROR: Invalid initial condition'
        endif
        call abort
     endif
  end select

  ! Ensure that initial conditions are divergence-free by performing a
  ! Helmholtz decomposition:
  call div_field_nul(ubk(:,:,:,1),ubk(:,:,:,2),ubk(:,:,:,3))
  call div_field_nul(ubk(:,:,:,4),ubk(:,:,:,5),ubk(:,:,:,6))
end subroutine init_fields_mhd


! The Orszag-Tang initial conditions for mhd.
subroutine init_orszagtang(ubk,ub)
  use mpi_header
  use mhd_vars
  implicit none

  complex(kind=pr),intent(inout):: ubk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nd)
  real(kind=pr),intent (inout) :: ub(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:nd)
  real(kind=pr) :: beta
  integer :: ix,iy,iz,i
  real(kind=pr) :: x,y,z

  beta=0.8d0

  do ix=ra(1),rb(1)
     x=xl*(dble(ix)/dble(nx) -0.5d0)
     do iy=ra(2),rb(2)
        y=yl*(dble(iy)/dble(ny) -0.5d0)
        do iz=ra(3),rb(3)
           z=zl*(dble(iz)/dble(nz) -0.5d0)

           ub(ix,iy,iz,1)=-2.d0*dsin(y)
           ub(ix,iy,iz,2)=2.d0*dsin(x)
           ub(ix,iy,iz,3)=0.d0

           ub(ix,iy,iz,4)=beta*(-2.d0*dsin(2.d0*y) + dsin(z))
           ub(ix,iy,iz,5)=beta*(2.d0*dsin(x) + dsin(z))
           ub(ix,iy,iz,6)=beta*(dsin(x) + dsin(y))
        enddo
     enddo
  enddo
  
  do i=1,nd
     call fft(ubk(:,:,:,i),ub(:,:,:,i))
  enddo
end subroutine init_orszagtang


! Constant initial conditions for MHD
subroutine init_const(ubk,wj)
  use mpi_header
  use mhd_vars
  implicit none

  complex(kind=pr),intent(inout):: ubk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nd)
  real(kind=pr),intent (inout) :: wj(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:nd)
  integer :: i

  wj(:,:,:,1)=1.d0
  wj(:,:,:,2)=2.d0
  wj(:,:,:,3)=3.d0

  wj(:,:,:,4)=4.d0
  wj(:,:,:,5)=5.d0
  wj(:,:,:,6)=6.d0

  do i=1,nd
     call fft(ubk(:,:,:,i),wj(:,:,:,i))
  enddo
end subroutine init_const


! The Sean-Montgomery-Chen initial conditions
subroutine init_smc(ubk,ub)
  use mpi_header
  use mhd_vars
  implicit none

  complex(kind=pr),intent(inout):: ubk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nd)
  real(kind=pr),intent (inout) :: ub(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:nd)
  integer :: i, ix,iy,iz
  real(kind=pr) :: x,y,r
  real (kind=pr) :: a,b,c,d,k1,k2,h

  ! Create a perturbation for the velocity field:
  call perturbation(ubk(:,:,:,1),ubk(:,:,:,2),ubk(:,:,:,3),&
       ub(:,:,:,1),ub(:,:,:,2),ub(:,:,:,3),&
       3.1017126d-07)

  ! Set up the magnetic field
  ub(:,:,:,4)=0.d0
  ub(:,:,:,5)=0.d0
  ub(:,:,:,6)=B0 ! bz set to B0 everywhere

  k1=Bc*r2/r1
  k2=Bc/r1
  A=(2.d0*k1 -k2*(r2-r3))/(r3*r3*r3 -3.d0*r2*r3*r3 +3.d0*r2*r2*r3 -r2*r2*r2)
  B=(k2 -3.d0*A*(r2*r2 -r3*r3))/(2.d0*r2 -2.d0*r3)
  C=-3.d0*A*r3*r3 -2.d0*B*r3
  D=2.d0*A*r3*r3*r3 +B*r3*r3

  do ix=ra(1),rb(1)
     x=xl*(dble(ix)/dble(nx) -0.5d0)
     do iy=ra(2),rb(2)
        y=yl*(dble(iy)/dble(ny) -0.5d0)
        
        r=dsqrt(x*x + y*y)

        if(r < r2) then
           do iz=ra(3),rb(3)
              ub(ix,iy,iz,4)=-y*Bc/R1
              ub(ix,iy,iz,5)= x*Bc/R1
           enddo
        endif

        if(r >= r2 .and. r <= r3) then
           h=(A*r*r*r +B*r*r +C*r +D)
           do iz=ra(3),rb(3)
              ub(ix,iy,iz,4)= h*y/r
              ub(ix,iy,iz,5)=-h*x/r
           enddo
        endif

     enddo
  enddo

  do i=3,nd
     call fft(ubk(:,:,:,i),ub(:,:,:,i))
  enddo
end subroutine init_smc


! The Taylor-Couette initial conditions for mhd.
subroutine init_tc_mhd(ubk,ub)
  use mpi_header
  use mhd_vars
  implicit none

  complex(kind=pr),intent(inout):: ubk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nd)
  real(kind=pr),intent (inout) :: ub(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:nd)
  
  ! Initialize the velocity field:
  call init_taylorcouette_u(ubk,ub)
  
  ! Create a perturbation for the magnetic field:
  call perturbation(ubk(:,:,:,4),ubk(:,:,:,5),ubk(:,:,:,6),&
       ub(:,:,:,4),ub(:,:,:,5),ub(:,:,:,6),&
       3.1017126d-07)

end subroutine init_tc_mhd
