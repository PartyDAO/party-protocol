// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Lightweight version of AuthenticatedProxy from
// https://etherscan.io/address/0x7f268357a8c2552623316e2562d90e642bb538e5#code
// that is shared across all Party instances.
contract WyvernProxy {
    using LibRawResult for bytes;

    error OnlyWyvernExchangeError(address caller, address exchange);
    error OnlyDaoError(address caller, address owner);
    error ProxyStoppedError();

    address public immutable EXCHANGE;
    bool public isStopped;
    IGlobals private immutable _GLOBALS;

    modifier onlyExchange() {
        // Only allow OS wyvern exchange to call.
        if (msg.sender != EXCHANGE) {
            revert OnlyWyvernExchangeError(msg.sender, EXCHANGE);
        }
        _;
    }

    modifier onlyDao() {
        // Only allow the owner to call.
        {
            address dao = _GLOBALS.getAddress(LibGobals.GLOBAL_DAO_WALLET);
            if (dao !=  msg.sender) {
                revert OnlyDaoError(msg.seder, dao);
            }
        }
        _;
    }

    modifier notStopped() {
        if (isStopped) {
            revert ProxyStoppedError();
        }
        _;
    }

    constructor(address exchange, ßIGlobals globals) {
        EXCHANGE = exchange;
        _GLOBALS = globals;
    }

    // Stop all transfers through this contract.
    function stop() external onlyDao {
        isStopped = true;
    }

    // Only supports ERC721 transfers.
    function proxy(
        address dest,
        IWyvernExchangeV2.HowToCall /* howToCall */,
        bytes calldata callData
    )
        external
        onlyExchange
        notStopped
        returns (bool result)
    {
        {
            bytes4 selector;
            assembly {
                selector := shr(224, calldataload(callData, 0))
            }
            if (selector != IERC721.safeTransferFrom.selector) {
                revert InvalidCallError(dest, callData);
            }
        }
        (bool s, bytes memory r) = dest.call(callData);
        if (!s) {
            r.rawRevert();
        }
        return true;
    }
}
