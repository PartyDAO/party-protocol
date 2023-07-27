// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "../tokens/IERC20.sol";

// Compatibility helpers for ERC20s.
library LibERC20Compat {
    error NotATokenError(IERC20 token);
    error TokenTransferFailedError(IERC20 token, address to, uint256 amount);
    error TokenApprovalFailed(IERC20 token, address spender, uint256 amount);

    // Perform an `IERC20.transfer()` handling non-compliant implementations.
    function compatTransfer(IERC20 token, address to, uint256 amount) internal {
        (bool s, bytes memory r) = address(token).call(
            abi.encodeCall(IERC20.transfer, (to, amount))
        );
        if (s) {
            if (r.length == 0) {
                uint256 cs;
                assembly {
                    cs := extcodesize(token)
                }
                if (cs == 0) {
                    revert NotATokenError(token);
                }
                return;
            }
            if (abi.decode(r, (bool))) {
                return;
            }
        }
        revert TokenTransferFailedError(token, to, amount);
    }

    // Perform an `IERC20.transferFrom()` handling non-compliant implementations.
    function compatTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        (bool s, bytes memory r) = address(token).call(
            abi.encodeCall(IERC20.transferFrom, (from, to, amount))
        );
        if (s) {
            if (r.length == 0) {
                uint256 cs;
                assembly {
                    cs := extcodesize(token)
                }
                if (cs == 0) {
                    revert NotATokenError(token);
                }
                return;
            }
            if (abi.decode(r, (bool))) {
                return;
            }
        }
        revert TokenTransferFailedError(token, to, amount);
    }

    function compatApprove(IERC20 token, address spender, uint256 amount) internal {
        (bool s, bytes memory r) = address(token).call(
            abi.encodeCall(IERC20.approve, (spender, amount))
        );
        if (s) {
            if (r.length == 0) {
                uint256 cs;
                assembly {
                    cs := extcodesize(token)
                }
                if (cs == 0) {
                    revert NotATokenError(token);
                }
                return;
            }
            if (abi.decode(r, (bool))) {
                return;
            }
        }
        revert TokenApprovalFailed(token, spender, amount);
    }
}
