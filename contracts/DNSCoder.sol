// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

error InvalidDNSName(bytes name);
error InvalidENSName(string name);

library DNSCoder {
    // WARNING: a label that contains a stop (.) will not round-trip
    // dnsDecode("3a.b0) => revert InvalidName
    // dnsEncode("a.b") = "1a1b0"
    // dnsDecode("1a1b0") = "a.b"

    // [ens]  "aaa.bb.c"
    // [dns] "3aaa2bb1c0"

    // ens.length = dns.length - 2
    // ens is offset 1-byte with lengths replaced with "."

    function decode(bytes memory dns) internal pure returns (string memory) {
        (bool ok, string memory ens) = tryDecode(dns);
        if (!ok) revert InvalidDNSName(dns);
        return ens;
    }

    function tryDecode(bytes memory dns) internal pure returns (bool ok, string memory) {
        unchecked {
            uint256 n = dns.length;
            if (n == 1 && dns[0] == 0) return (true, ""); // only valid answer is root
            if (n < 3) return (false, ""); // invalid
            bytes memory ens = new bytes(n - 2); // always 2-shorter
            uint256 src = 0;
            uint256 dst = 0;
            while (src < n) {
                uint8 len = uint8(dns[src++]);
                if (len == 0) break;
                uint256 end = src + len;
                if (end > dns.length) return (false, ""); // overflow
                if (dst > 0) ens[dst++] = ".";
                while (src < end) {
                    bytes1 c = dns[src++];
                    if (c == ".") return (false, ""); // malicious label
                    ens[dst++] = c;
                }
            }
            if (src != dns.length) return (false, ""); // junk at end
            return (true, string(ens));
        }
    }

    function encode(string memory ens) internal pure returns (bytes memory) {
        (bool ok, bytes memory dns) = tryEncode(ens);
        if (!ok) revert InvalidENSName(ens);
        return dns;
    }

    function tryEncode(string memory ens) internal pure returns (bool ok, bytes memory dns) {
        unchecked {
            uint256 n = bytes(ens).length;
            if (n == 0) return (true, hex"00"); // root
            dns = new bytes(n + 2); // always 2-longer
            uint256 w;
            uint256 e;
            uint256 r;
            assembly {
                e := add(dns, 32)
                r := e // remember start
                ens := add(ens, 32)
                for { let i := 0 } lt(i, n) { i := add(i, 1) } {
                    let b := shr(248, mload(add(ens, i))) // read byte
                    if eq(b, 46) {
                        w := sub(e, r) // length of label
                        if or(iszero(w), gt(w, 255)) { break } // something wrong
                        mstore8(r, w) // store length at start
                        r := add(e, 1) // update start
                    }
                    {
                        e := add(e, 1)
                        mstore8(e, b)
                    }
                }
            }
            w = e - r; // length of last label
            if (w == 0 || w > 255) return (false, "");
            assembly {
                mstore8(r, w) // store length
            }
            return (true, dns);
        }
    }
}
