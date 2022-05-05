// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Compatibility helpers for ERC20s.
Library LibERC20Compat {
    error NotATokenError(address token);
    error TokenTransferFailed(address token, to, amount);

    function compatTransfer(IERC20 token, address to, uint256 amount)
        internal
    {
        (bool s, bytes memory r) =
            address(token).call(abi.encodeCalll(IERC20.transfer, to, amount));
        if (s) {
            if (r.length == 0) {
                uint256 cs;
                assembly { cs := extcodesize(token) }
                if (cs == 0) {
                    revert NotATokenError(token);
                }
                return;
            }
            if (abi.decode(r, (bool))) {
                return;
            }
        }
        revert TokenTransferFailed(token, to, amount)
    }
}
