!  Calculate visfusive term for time advancement,
!  exp (-nu*k^2*dt)
!  It is real valued, its global size is 0:nz-1, 0:nx/2, 0:ny-1 
!  This is computed only if the time step changes. Is does rarely,
!  because we round it to one digit.  also, dealiasing is done here
!  (multiply aliased avenumbers by zero
subroutine cal_vis(dt,vis)
  use vars
  use mpi_header
  implicit none

  integer :: ix,iy,iz
  real(kind=pr),intent(inout) :: vis(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nf)
  real(kind=pr),intent(in) :: dt
  real(kind=pr) :: kx2,ky2,kz2,t1,kxt2,kyt2,kzt2,kx_trunc,ky_trunc,kz_trunc
  integer :: i

  t1=MPI_wtime()

  kx_trunc=(2.d0/3.d0)*dble(nx/2-1)
  ky_trunc=(2.d0/3.d0)*dble(ny/2-1)
  kz_trunc=(2.d0/3.d0)*dble(nz/2-1)  

  do iz=ca(1),cb(1)
     kz2 =(scalez*dble(modulo(iz+nz/2,nz)-nz/2))**2
     kzt2=dble(modulo(iz+nz/2,nz)-nz/2)/kz_trunc
     kzt2=kzt2*kzt2
     
     do ix=ca(2),cb(2)
        ! kx - x-wavenumber: 0..nx/2
        kx2=(scalex*dble(ix))**2
        kxt2=dble(ix)/kx_trunc
        kxt2=kxt2*kxt2

        do iy=ca(3),cb(3)
           ! ky - y-wavenumber: 0..ny/2-1 ,then, -ny/2..-1
           ky2=(scaley*dble(modulo(iy+ny/2,ny)-ny/2))**2
           kyt2=dble(modulo(iy+ny/2,ny)-ny/2)/ky_trunc
           kyt2=kyt2*kyt2

           ! Dealiasing is done here for reasons of efficiency
           do i=1,nf
              if ((kxt2 + kyt2 + kzt2  .ge. 1.d0) .and. (iDealias==1)) then
                 vis(iz,ix,iy,i)=0.d0
              else
                 vis(iz,ix,iy,i)=dexp( -dt*lin(i)*(kx2 + ky2 + kz2) )
              endif
           enddo

        enddo
     enddo
  enddo

  time_vis=time_vis + MPI_wtime() - t1 
end subroutine cal_vis
