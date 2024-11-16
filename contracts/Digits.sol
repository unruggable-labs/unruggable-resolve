// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Digits {
    function length(
        uint256 value,
        uint256 base
    ) internal pure returns (uint256 len) {
        if (base > 0) len = 1;
        while (value > base) {
            value /= base;
            len += 1;
        }
    }

    function appendHex(
        uint256 ptr,
        bytes memory v
    ) internal pure returns (uint256 dst) {
        unchecked {
            uint256 src;
            uint256 len;
            assembly {
                src := add(v, 32)
                len := mload(v)
            }
            while (len >= 32) {
                uint256 x;
                assembly {
                    x := mload(src)
                    src := add(src, 32)
                    len := sub(len, 32)
                }
                ptr = append(ptr, 64, x, 16);
            }
            if (len > 0) {
                uint256 x;
                assembly {
                    x := mload(sub(src, sub(32, len)))
                }
                ptr = append(ptr, len << 1, x, 16);
            }
            return ptr;
        }
    }

    function append(
        uint256 ptr,
        uint256 len,
        uint256 value,
        uint256 base
    ) internal pure returns (uint256 dst) {
        unchecked {
            if (len == 0) len = length(value, base);
            dst = ptr + len;
            while (len > 0) {
                uint256 x = value % base;
                value /= base;
                uint256 cp = (x < 10 ? 48 + x : 87 + x); // "0" => 48, ("a" - 10) => 87
                --len;
                assembly {
                    mstore8(add(ptr, len), cp)
                }
            }
        }
    }
}
