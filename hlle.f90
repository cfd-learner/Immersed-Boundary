module hlle
    !-------------------------------------------------------------------
    ! The HLLE scheme is a type of flux-splitting scheme
    !-------------------------------------------------------------------

    use utils, only: alloc, dealloc, dmsg
    use grid, only: imx, jmx
    use geometry, only: xnx, xny, ynx, yny, xA, yA
    use state, only: gm
    use face_interpolant, only: x_qp_left, x_qp_right, y_qp_left, y_qp_right, &
            x_density_left, x_x_speed_left, x_y_speed_left, x_pressure_left, &
            x_density_right, x_x_speed_right, x_y_speed_right, &
                x_pressure_right, &
            y_density_left, y_x_speed_left, y_y_speed_left, y_pressure_left, &
            y_density_right, y_x_speed_right, y_y_speed_right, &
                y_pressure_right, &
            x_sound_speed_left, x_sound_speed_right, &
            y_sound_speed_left, y_sound_speed_right

    implicit none
    private
    real, dimension(:, :), allocatable :: x_alpha_left, x_alpha_right
    real, dimension(:, :), allocatable :: x_face_normal_speed_left, &
            x_face_normal_speed_right
    real, dimension(:, :), allocatable :: x_total_enthalpy_left, &
            x_total_enthalpy_right
    real, dimension(:, :), allocatable :: y_alpha_left, y_alpha_right
    real, dimension(:, :), allocatable :: y_face_normal_speed_left, &
            y_face_normal_speed_right
    real, dimension(:, :), allocatable :: y_total_enthalpy_left, &
            y_total_enthalpy_right
    real, public, dimension(:, :, :), allocatable, target :: F, G

    ! Public members
    public :: setup_scheme
    public :: destroy_scheme
    public :: compute_face_quantities
    public :: compute_fluxes
    public :: get_residue

    contains

        subroutine setup_scheme()

            implicit none

            call dmsg(1, 'hlle', 'setup_scheme')

            call alloc(x_alpha_left, 1, imx, 1, jmx-1, &
                    errmsg='Error: Unable to allocate memory for ' // &
                        'x_alpha_left.')
            call alloc(x_alpha_right, 1, imx, 1, jmx-1, &
                    errmsg='Error: Unable to allocate memory for ' // &
                        'x_alpha_right.')
            call alloc(y_alpha_left, 1, imx-1, 1, jmx, &
                    errmsg='Error: Unable to allocate memory for ' // &
                        'y_alpha_left.')
            call alloc(y_alpha_right, 1, imx-1, 1, jmx, &
                    errmsg='Error: Unable to allocate memory for ' // &
                        'y_alpha_right.')

            call alloc(x_face_normal_speed_left, 1, imx, 1, jmx-1, &
                    errmsg='Error: Unable to allocate memory for ' // &
                        'x_face_normal_speed_left.')
            call alloc(x_face_normal_speed_right, 1, imx, 1, jmx-1, &
                    errmsg='Error: Unable to allocate memory for ' // &
                        'x_face_normal_speed_right.')
            call alloc(y_face_normal_speed_left, 1, imx-1, 1, jmx, &
                    errmsg='Error: Unable to allocate memory for ' // &
                        'y_face_normal_speed_left.')
            call alloc(y_face_normal_speed_right, 1, imx-1, 1, jmx, &
                    errmsg='Error: Unable to allocate memory for ' // &
                        'y_face_normal_speed_right.')

            call alloc(x_total_enthalpy_left, 1, imx, 1, jmx-1, &
                    errmsg='Error: Unable to allocate memory for ' // &
                        'x_total_enthalpy_left.')
            call alloc(x_total_enthalpy_right, 1, imx, 1, jmx-1, &
                    errmsg='Error: Unable to allocate memory for ' // &
                        'x_total_enthalpy_right.')
            call alloc(y_total_enthalpy_left, 1, imx-1, 1, jmx, &
                    errmsg='Error: Unable to allocate memory for ' // &
                        'y_total_enthalpy_left.')
            call alloc(y_total_enthalpy_right, 1, imx-1, 1, jmx, &
                    errmsg='Error: Unable to allocate memory for ' // &
                        'y_total_enthalpy_right.')

            call alloc(F, 1, imx, 1, jmx-1, 1, 4, &
                    errmsg='Error: Unable to allocate memory for ' // &
                        'F.')
            call alloc(G, 1, imx-1, 1, jmx, 1, 4, &
                    errmsg='Error: Unable to allocate memory for ' // &
                        'G.')

        end subroutine setup_scheme

        subroutine destroy_scheme()

            implicit none

            call dmsg(1, 'hlle', 'destroy_scheme')

            call dealloc(F)
            call dealloc(G)

            call dealloc(x_alpha_left)
            call dealloc(x_alpha_right)
            call dealloc(y_alpha_left)
            call dealloc(y_alpha_right)

            call dealloc(x_face_normal_speed_left)
            call dealloc(x_face_normal_speed_right)
            call dealloc(y_face_normal_speed_left)
            call dealloc(y_face_normal_speed_right)
            
            call dealloc(x_total_enthalpy_left)
            call dealloc(x_total_enthalpy_right)
            call dealloc(y_total_enthalpy_left)
            call dealloc(y_total_enthalpy_right)

        end subroutine destroy_scheme

        function weighted_avg(w1, w2, var1, var2)

            implicit none
            real, dimension(:, :), intent(in) :: w1, w2
            real, dimension(:, :), intent(in) :: var1, var2
            real, dimension(1:size(var1, 1), 1:size(var1, 2)) :: weighted_avg

            weighted_avg = ((w1 * var1) + (w2 * var2)) / (w1 + w2)

        end function weighted_avg

        function get_x_sound_speed_avg() result(x_sound_speed_avg)
            !-----------------------------------------------------------
            ! In HLLE, the averaged sound speed is derived from the 
            ! Roe-averaged total enthalpy, x_speed and y_speed.
            !-----------------------------------------------------------

            implicit none
            real, dimension(1:imx, 1:jmx-1) :: x_sound_speed_avg
            real, dimension(1:imx, 1:jmx-1) :: x_total_enthalpy_avg
            real, dimension(1:imx, 1:jmx-1) :: x_x_speed_avg, x_y_speed_avg

            x_total_enthalpy_avg = weighted_avg( &
                    sqrt(x_density_left), sqrt(x_density_right), &
                    x_total_enthalpy_left, x_total_enthalpy_right &
                    )
            x_x_speed_avg = weighted_avg( &
                    sqrt(x_density_left), sqrt(x_density_right), &
                    x_x_speed_left, x_x_speed_right &
                    )
            x_y_speed_avg = weighted_avg( &
                    sqrt(x_density_left), sqrt(x_density_right), &
                    x_y_speed_left, x_y_speed_right &
                    )

            x_sound_speed_avg = sqrt((gm - 1) * &
                    (x_total_enthalpy_avg - &
                    0.5 * (x_x_speed_avg ** 2. + x_y_speed_avg ** 2.)))

        end function get_x_sound_speed_avg

        subroutine compute_xi_face_quantities()
            !-----------------------------------------------------------
            ! Compute xi direction quantities used in F flux computation
            !-----------------------------------------------------------

            implicit none

            real, dimension(1:imx, 1:jmx-1) :: x_face_normal_speed_avg
            real, dimension(1:imx, 1:jmx-1) :: x_sound_speed_avg

            call dmsg(1, 'hlle', 'compute_xi_face_quantities')

            ! Compute face normal speeds (left and right)
            x_face_normal_speed_left = x_x_speed_left * xnx + &
                    x_y_speed_left * xny
            x_face_normal_speed_right = x_x_speed_right * xnx + &
                    x_y_speed_right * xny

            ! Compute Roe-averaged face normal speed
            x_face_normal_speed_avg = weighted_avg( &
                    sqrt(x_density_left), sqrt(x_density_right), &
                    x_face_normal_speed_left, x_face_normal_speed_right &
                    )

            ! Compute total enthalpy (left and right)
            x_total_enthalpy_left = &
                    ((gm / (gm - 1)) * x_pressure_left / x_density_left) + &
                    (0.5 * (x_x_speed_left ** 2. + x_y_speed_left ** 2.))
            x_total_enthalpy_right = &
                    ((gm / (gm - 1)) * x_pressure_right / x_density_right) + &
                    (0.5 * (x_x_speed_right ** 2. + x_y_speed_right ** 2.))

            ! Compute Roe-averaged sound speed
            x_sound_speed_avg = get_x_sound_speed_avg()

            ! Compute alphas
            x_alpha_left = max(0., &
                    x_face_normal_speed_avg + x_sound_speed_avg, &
                    x_face_normal_speed_right + x_sound_speed_right() &
                    )
            x_alpha_right = min(0., &
                    x_face_normal_speed_avg - x_sound_speed_avg, &
                    x_face_normal_speed_left - x_sound_speed_left() &
                    )

        end subroutine compute_xi_face_quantities

        function F_left()

            implicit none
            real, dimension(1:imx, 1:jmx-1, 1:4) :: F_left
            integer :: k

            F_left(:, :, 1) = x_density_left * &
                    (x_face_normal_speed_left - x_alpha_right)
            F_left(:, :, 2) = F_left(:, :, 1) * x_x_speed_left + &
                    x_pressure_left * xnx
            F_left(:, :, 3) = F_left(:, :, 1) * x_y_speed_left + &
                    x_pressure_left * xny
            F_left(:, :, 4) = F_left(:, :, 1) * x_total_enthalpy_left + &
                    x_alpha_right * x_pressure_left

            do k = 1, 4
                F_left(:, :, k) = F_left(:, :, k) * x_alpha_left / &
                        (x_alpha_left - x_alpha_right)
            end do
            
            ! Multiply in the face areas
            F_left(:, :, 1) = F_left(:, :, 1) * xA
            F_left(:, :, 2) = F_left(:, :, 2) * xA
            F_left(:, :, 3) = F_left(:, :, 3) * xA
            F_left(:, :, 4) = F_left(:, :, 4) * xA

        end function F_left

        function F_right()

            implicit none
            real, dimension(1:imx, 1:jmx-1, 1:4) :: F_right
            integer :: k

            F_right(:, :, 1) = x_density_right * &
                    (x_face_normal_speed_right - x_alpha_left)
            F_right(:, :, 2) = F_right(:, :, 1) * x_x_speed_right + &
                    x_pressure_right * xnx
            F_right(:, :, 3) = F_right(:, :, 1) * x_y_speed_right + &
                    x_pressure_right * xny
            F_right(:, :, 4) = F_right(:, :, 1) * x_total_enthalpy_right + &
                    x_alpha_left * x_pressure_right

            do k = 1, 4
                F_right(:, :, k) = F_right(:, :, k) * x_alpha_right / &
                        (x_alpha_left - x_alpha_right)
            end do
            ! Multiply in the face areas
            F_right(:, :, 1) = F_right(:, :, 1) * xA
            F_right(:, :, 2) = F_right(:, :, 2) * xA
            F_right(:, :, 3) = F_right(:, :, 3) * xA
            F_right(:, :, 4) = F_right(:, :, 4) * xA

        end function F_right

        function get_y_sound_speed_avg() result(y_sound_speed_avg)
            !-----------------------------------------------------------
            ! In HLLE, the averaged sound speed is derived from the 
            ! Roe-averaged total enthalpy, x_speed and y_speed.
            !-----------------------------------------------------------

            implicit none
            real, dimension(1:imx-1, 1:jmx) :: y_sound_speed_avg
            real, dimension(1:imx-1, 1:jmx) :: y_total_enthalpy_avg
            real, dimension(1:imx-1, 1:jmx) :: y_x_speed_avg, y_y_speed_avg

            y_total_enthalpy_avg = weighted_avg( &
                    sqrt(y_density_left), sqrt(y_density_right), &
                    y_total_enthalpy_left, y_total_enthalpy_right &
                    )
            y_x_speed_avg = weighted_avg( &
                    sqrt(y_density_left), sqrt(y_density_right), &
                    y_x_speed_left, y_x_speed_right &
                    )
            y_y_speed_avg = weighted_avg( &
                    sqrt(y_density_left), sqrt(y_density_right), &
                    y_y_speed_left, y_y_speed_right &
                    )

            y_sound_speed_avg = sqrt((gm - 1) * &
                    (y_total_enthalpy_avg - &
                    0.5 * (y_x_speed_avg ** 2. + y_y_speed_avg ** 2.)))

        end function get_y_sound_speed_avg

        subroutine compute_eta_face_quantities()
            !-----------------------------------------------------------
            ! Compute eta direction quantities used in G flux computation
            !-----------------------------------------------------------

            implicit none

            real, dimension(1:imx-1, 1:jmx) :: y_face_normal_speed_avg
            real, dimension(1:imx-1, 1:jmx) :: y_sound_speed_avg

            call dmsg(1, 'hlle', 'compute_eta_face_quantities')

            ! Compute face normal speeds (left and right)
            y_face_normal_speed_left = y_x_speed_left * ynx + &
                    y_y_speed_left * yny
            y_face_normal_speed_right = y_x_speed_right * ynx + &
                    y_y_speed_right * yny

            ! Compute Roe-averaged face normal speed
            y_face_normal_speed_avg = weighted_avg( &
                    sqrt(y_density_left), sqrt(y_density_right), &
                    y_face_normal_speed_left, y_face_normal_speed_right &
                    )

            ! Compute total enthalpy (left and right)
            y_total_enthalpy_left = &
                    ((gm / (gm - 1)) * y_pressure_left / y_density_left) + &
                    (0.5 * (y_x_speed_left ** 2. + y_y_speed_left ** 2.))
            y_total_enthalpy_right = &
                    ((gm / (gm - 1)) * y_pressure_right / y_density_right) + &
                    (0.5 * (y_x_speed_right ** 2. + y_y_speed_right ** 2.))

            ! Compute Roe-averaged sound speed
            y_sound_speed_avg = get_y_sound_speed_avg()

            ! Compute alphas
            y_alpha_left = max(0., &
                    y_face_normal_speed_avg + y_sound_speed_avg, &
                    y_face_normal_speed_right + y_sound_speed_right() &
                    )
            y_alpha_right = min(0., &
                    y_face_normal_speed_avg - y_sound_speed_avg, &
                    y_face_normal_speed_left - y_sound_speed_left() &
                    )

        end subroutine compute_eta_face_quantities

        function G_left()

            implicit none
            real, dimension(1:imx-1, 1:jmx, 1:4) :: G_left
            integer :: k

            G_left(:, :, 1) = y_density_left * &
                    (y_face_normal_speed_left - y_alpha_right)
            G_left(:, 1, 1) = 0.0
        !   G_left(:, jmx, 1) = 0.0
            G_left(:, :, 2) = G_left(:, :, 1) * y_x_speed_left + &
                    y_pressure_left * ynx
            G_left(:, :, 3) = G_left(:, :, 1) * y_y_speed_left + &
                    y_pressure_left * yny
            G_left(:, :, 4) = G_left(:, :, 1) * y_total_enthalpy_left + &
                    y_alpha_right * y_pressure_left
            
            do k = 1, 4
                G_left(:, :, k) = G_left(:, :, k) * y_alpha_left / &
                        (y_alpha_left - y_alpha_right)
            end do
            
            ! Multiply in the face areas
            G_left(:, :, 1) = G_left(:, :, 1) * yA
            G_left(:, :, 2) = G_left(:, :, 2) * yA
            G_left(:, :, 3) = G_left(:, :, 3) * yA
            G_left(:, :, 4) = G_left(:, :, 4) * yA
        
        end function G_left

        function G_right()

            implicit none
            real, dimension(1:imx-1, 1:jmx, 1:4) :: G_right
            integer :: k

            G_right(:, :, 1) = y_density_right * &
                    (y_face_normal_speed_right - y_alpha_left)
            G_right(:, 1, 1) = 0.0
        !   G_right(:, jmx, 1) = 0.0
            G_right(:, :, 2) = G_right(:, :, 1) * y_x_speed_right + &
                    y_pressure_right * ynx
            G_right(:, :, 3) = G_right(:, :, 1) * y_y_speed_right + &
                    y_pressure_right * yny
            G_right(:, :, 4) = G_right(:, :, 1) * y_total_enthalpy_right + &
                    y_alpha_left * y_pressure_right

            do k = 1, 4
                G_right(:, :, k) = G_right(:, :, k) * y_alpha_right / &
                        (y_alpha_left - y_alpha_right)
            end do

            ! Multiply in the face areas
            G_right(:, :, 1) = G_right(:, :, 1) * yA
            G_right(:, :, 2) = G_right(:, :, 2) * yA
            G_right(:, :, 3) = G_right(:, :, 3) * yA
            G_right(:, :, 4) = G_right(:, :, 4) * yA

        end function G_right
        
        subroutine compute_face_quantities()

            implicit none

            call dmsg(1, 'hlle', 'compute_face_quantities')
            call compute_xi_face_quantities()
            call compute_eta_face_quantities()

        end subroutine compute_face_quantities

        subroutine compute_fluxes()

            implicit none
            
            call dmsg(1, 'hlle', 'compute_fluxes')

            F = F + F_left() - F_right()
            if (any(isnan(F))) then
                call dmsg(5, 'hlle', 'compute_flux', 'ERROR: F flux Nan detected')
                stop
            end if

            G = G + G_left() - G_right()
            if (any(isnan(G))) then
                call dmsg(5, 'hlle', 'compute_flux', 'ERROR: F flux Nan detected')
                stop
            end if

        end subroutine compute_fluxes

        function get_residue() result(residue)
            !-----------------------------------------------------------
            ! Return the HLLE residue
            !-----------------------------------------------------------
            
            implicit none
            real, dimension(imx-1, jmx-1, 4) :: residue

            call dmsg(1, 'hlle', 'get_residue')

            residue = F(2:imx, 1:jmx-1, :) &
                    - F(1:imx-1, 1:jmx-1, :) &
                    + G(1:imx-1, 2:jmx, :) &
                    - G(1:imx-1, 1:jmx-1, :)

        end function get_residue

end module hlle
