// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DNSCoder, MalformedDNSEncoding, DNSEncodingFailed} from "../contracts/DNSCoder.sol";
import "forge-std/Test.sol";

contract TestDNSCoder is Test {
    function test_root() external pure {
        _testValid("", hex"00", 0x000000000000000000000000000000000000000000000000000000000000000000);
    }

    function test_eth() external pure {
        _testValid("eth", hex"0365746800", 0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae);
    }

    function test_raffy_eth() external pure {
        _testValid(
            "raffy.eth", hex"0572616666790365746800", 0x9c8b7ac505c9f0161bbbd04437fce8c630a0886e1ffea00078e298f063a8a5df
        );
    }

    function test_a_bb_ccc_dddd_eeeee_ffffff() external pure {
        _testValid(
            "a.bb.ccc.dddd.eeeee.ffffff",
            hex"01610262620363636304646464640565656565650666666666666600",
            0x67708687406f50102b1dd9042f5c76f017b1ddfb9086878e4dedb9e0a4ff60d1
        );
    }

    function test_encodedLabel() external pure {
        // `[${keccak256(raffy)}].eth`
        (bytes32 node,) = DNSCoder.namehash(
            hex"425b636230636263383439336261663461376231393732393134626130626538393034306535366534613363393864363032363866653337623863386535343664395d0365746800",
            0
        );
        assertEq(node, 0x9c8b7ac505c9f0161bbbd04437fce8c630a0886e1ffea00078e298f063a8a5df);
    }

    function test_emptyLabel() external {
        _testInvalidENS(".");
        _testInvalidENS("..");
        _testInvalidENS("a.");
        _testInvalidENS(".b");
        _testInvalidENS("a..b");
    }

    function test_largeLabel() external {
        bytes memory a = bytes("a");
        while (a.length < 256) a = bytes.concat(a, a);
        _testInvalidENS(string(a));
    }

    function test_labelWithStop() external {
        _testMalformedDNS(bytes("\x03a.b\x00"));
    }

    function test_malformedEncoding() external {
        _testMalformedDNS(hex"");
        _testMalformedDNS(hex"02");
        _testMalformedDNS(hex"0000");
        _testMalformedDNS(hex"0100");
    }

    function _testValid(string memory ens, bytes memory dns, bytes32 node) internal pure {
        assertEq(DNSCoder.decode(dns), ens);
        assertEq(DNSCoder.encode(ens), dns);
        (bytes32 computed,) = DNSCoder.namehash(dns, 0);
        assertEq(computed, node);
    }

    function _testInvalidENS(string memory ens) internal {
        vm.expectRevert(abi.encodeWithSelector(DNSEncodingFailed.selector, ens));
        DNSCoder.encode(ens);
    }

    function _testMalformedDNS(bytes memory dns) internal {
        vm.expectRevert(abi.encodeWithSelector(MalformedDNSEncoding.selector, dns));
        DNSCoder.decode(dns);
        vm.expectRevert(abi.encodeWithSelector(MalformedDNSEncoding.selector, dns));
        DNSCoder.namehash(dns, 0);
    }
}
