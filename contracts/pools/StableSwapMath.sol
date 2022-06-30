// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

library StableSwapMath {
    uint256 private constant A_PRECISION = 100;
    uint256 private constant PRECISION = 10**18;
    uint256 private constant FEE_DENOMINATOR = 10**10;

    function getD(uint256[] memory xp, uint256 amp) public pure returns (uint256) {
        uint256 S = 0;
        uint256 N_COINS = xp.length;
        for (uint256 i = 0; i < N_COINS; i++) {
            S += xp[i];
        }
        if (S == 0) {
            return 0;
        }

        uint256 Dprev = 0;
        uint256 D = S;
        uint256 Ann = amp * N_COINS;
        for (uint256 _i = 0; _i < 255; _i++) {
            uint256 DP = D;
            for (uint256 _j = 0; _j < N_COINS; _j++) {
                DP = (DP * D) / (xp[_j] * N_COINS); // If division by 0, this will be borked: only withdrawal will work. And that is good
            }
            Dprev = D;
            uint256 sum = (Ann * S) / A_PRECISION + DP * N_COINS;
            // protect overflow with unbalanced liquidity
            // scaling factor is heuristic value, so it might be changed
            uint256 SCALING_FACTOR = 1;
            if (sum > type(uint256).max / D / 100) {
                SCALING_FACTOR = 10**18;
            }
            D = (((sum / SCALING_FACTOR) * D) / (((Ann - A_PRECISION) * D) / A_PRECISION + (N_COINS + 1) * DP)) * SCALING_FACTOR;
            // Equality with the precision of 1
            if (D > Dprev) {
                if (D - Dprev <= 1) return D;
            } else {
                if (Dprev - D <= 1) return D;
            }
        }
        // convergence typically occurs in 4 rounds or less, this should be unreachable!
        // if it does happen the pool is borked and LPs can withdraw via `removeLiquidity`
        revert();
    }

    function getY(
        uint256 i,
        uint256 j,
        uint256 x,
        uint256[] memory xp_,
        uint256 amp
    ) public pure returns (uint256) {
        // x in the input is converted to the same price/precision
        uint256 N_COINS = xp_.length;

        require(i != j); // dev: same coin
        require(j >= 0); // dev: j below zero
        require(j < N_COINS); // dev: j above N_COINS

        // should be unreachable, but good for safety
        require(i >= 0);
        require(i < N_COINS);

        uint256 D = getD(xp_, amp);

        uint256 S_ = 0;
        uint256 _x = 0;
        uint256 c = D;
        uint256 Ann = amp * N_COINS;

        for (uint256 _i = 0; _i < N_COINS; _i++) {
            if (_i == i) {
                _x = x;
            } else if (_i != j) {
                _x = xp_[_i];
            } else {
                continue;
            }
            S_ += _x;
            c = (c * D) / (_x * N_COINS);
        }
        c = (c * D * A_PRECISION) / (Ann * N_COINS);
        uint256 b = S_ + (D * A_PRECISION) / Ann; // - D
        uint256 yPrev = 0;
        uint256 y = D;
        for (uint256 _i = 0; _i < 255; _i++) {
            yPrev = y;
            y = (y * y + c) / (2 * y + b - D);
            // Equality with the precision of 1
            if (y > yPrev) {
                if (y - yPrev <= 1) {
                    return y;
                }
            } else {
                if (yPrev - y <= 1) {
                    return y;
                }
            }
        }
        revert();
    }

    function getYD(
        uint256 A_,
        uint256 i,
        uint256[] memory xp,
        uint256 D
    ) external pure returns (uint256) {
        uint256 N_COINS = xp.length;
        /*
        Calculate x[i] if one reduces D from being calculated for xp to D

        Done by solving quadratic equation iteratively.
        x_1**2 + x1 * (sum' - (A*n**n - 1) * D / (A * n**n)) = D ** (n + 1) / (n ** (2 * n) * prod' * A)
        x_1**2 + b*x_1 = c

        x_1 = (x_1**2 + c) / (2*x_1 + b)
        */
        // x in the input is converted to the same price/precision

        require(i >= 0); // dev: i below zero
        require(i < N_COINS); // dev: i above N_COINS

        uint256 S_ = 0;
        uint256 _x = 0;

        uint256 c = D;
        uint256 Ann = A_ * N_COINS;

        for (uint256 _i = 0; _i < N_COINS; _i++) {
            if (_i != i) {
                _x = xp[_i];
            } else {
                continue;
            }
            S_ += _x;
            c = (c * D) / (_x * N_COINS);
        }
        c = (c * D * A_PRECISION) / (Ann * N_COINS);
        uint256 b = S_ + (D * A_PRECISION) / Ann;
        uint256 yPrev = 0;
        uint256 y = D;
        for (uint256 _i = 0; _i < 255; _i++) {
            yPrev = y;
            y = (y * y + c) / (2 * y + b - D);
            // Equality with the precision of 1
            if (y > yPrev) {
                if (y - yPrev <= 1) {
                    return y;
                }
            } else {
                if (yPrev - y <= 1) {
                    return y;
                }
            }
        }
        revert();
    }

    function calculatePrice(
        uint256 i,
        uint256 j,
        uint256[] memory xp,
        uint256 amp
    ) external pure returns (uint256) {
        if (i == j) {
            return PRECISION;
        }
        uint256 N_COINS = xp.length;
        uint256 D = getD(xp, amp);
        uint256 c = (PRECISION * D) / N_COINS;
        for (uint256 k = 0; k < N_COINS; k++) {
            c = (c * D) / N_COINS / xp[k];
        }
        return ((amp * PRECISION + (c / xp[i]) * A_PRECISION) * PRECISION) / (amp * PRECISION + (c / xp[j]) * A_PRECISION);
    }

    function calculateLpPrice(
        uint256 i,
        uint256[] memory xp,
        uint256 amp,
        uint256 lpSupply
    ) external pure returns (uint256) {
        uint256 N_COINS = xp.length;
        uint256 D = getD(xp, amp);
        uint256 p = PRECISION;
        uint256 ANN = amp * N_COINS;
        for (uint256 k = 0; k < N_COINS; k++) {
            p = p * D / N_COINS / xp[k];
        }
        return PRECISION * D * (ANN * PRECISION - A_PRECISION * PRECISION + (N_COINS + 1) * p * A_PRECISION) / (ANN * PRECISION + p * D * A_PRECISION / xp[i]) / lpSupply;
    }

    function calculateDy(
        uint256[] memory rates,
        uint256[] memory xp,
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 amp,
        uint256 fee
    ) external pure returns (uint256) {
        uint256 x = xp[i] + ((dx * rates[i]) / PRECISION);
        uint256 y = getY(i, j, x, xp, amp);
        uint256 dy = xp[j] - y - 1;
        uint256 _fee = (fee * dy) / FEE_DENOMINATOR;
        return ((dy - _fee) * PRECISION) / rates[j];
    }

    function calculateDx(
        uint256[] memory rates,
        uint256[] memory xp,
        uint256 i,
        uint256 j,
        uint256 dy,
        uint256 amp,
        uint256 fee
    ) external pure returns (uint256) {
        uint256 y = xp[j] - (((dy * FEE_DENOMINATOR) / (FEE_DENOMINATOR - fee)) * rates[j]) / PRECISION;
        uint256 x = getY(j, i, y, xp, amp);
        return ((x - xp[i]) * PRECISION) / rates[i];
    }
}
