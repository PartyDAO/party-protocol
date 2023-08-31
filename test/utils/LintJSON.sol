// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { Strings } from "../../contracts/utils/vendor/Strings.sol";
import { Test } from "forge-std/Test.sol";
import { Base64 } from "./FullBase64.sol";

contract LintJSON is Test {
    using Base64 for string;
    using Strings for string;

    function _lintEncodedJSON(string memory base64EncodedJSON) internal {
        string memory prefixRemoved = base64EncodedJSON.substring(
            29,
            bytes(base64EncodedJSON).length
        );
        bytes memory utf8EncodedJSON = prefixRemoved.decode();
        string memory json;
        assembly {
            json := utf8EncodedJSON
        }
        _lintJSON(json);
    }

    function _lintJSON(string memory json) internal {
        vm.writeFile("./out/lint-json.json", json);
        string[] memory inputs = new string[](2);
        inputs[0] = "node";
        inputs[1] = "./js/lint-json.js";
        bytes memory ffiResp = vm.ffi(inputs);
        vm.removeFile("./out/lint-json.json");

        uint256 resAsInt;
        assembly {
            resAsInt := mload(add(ffiResp, 0x20))
        }
        if (resAsInt != 1) {
            revert("JSON lint failed");
        }
    }
}
