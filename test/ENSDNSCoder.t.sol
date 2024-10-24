// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ENSDNSCoder} from "../contracts/utils/ENSDNSCoder.sol";
import "forge-std/Test.sol";

contract TestENSDNSCoder is Test {
    function test_root() external pure {
        _testValid("", hex"00");
    }
	function test_eth() external pure {
        _testValid("eth", hex"0365746800");
    }
    function test_raffy_eth() external pure {
        _testValid("raffy.eth", hex"0572616666790365746800");
    }
	function test_a_bb_ccc_dddd_eeeee_ffffff() external pure {
        _testValid("a.bb.ccc.dddd.eeeee.ffffff", hex"01610262620363636304646464640565656565650666666666666600");
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
		while (a.length < 256) {
			a = bytes.concat(a, a);
		} 
		_testInvalidENS(string(a));
	}
    function test_stoppedLabel() external {
        _testInvalidDNS(bytes("\x03a.b\x00"));
    }
    function test_wrongEncoding() external {
        _testInvalidDNS(hex"");
        _testInvalidDNS(hex"02");
        _testInvalidDNS(hex"0000");
        _testInvalidDNS(hex"0100");
    }

    function _testValid(string memory ens, bytes memory dns) internal pure {
        assertEq(ENSDNSCoder.dnsDecode(dns), ens);
        assertEq(ENSDNSCoder.dnsEncode(ens), dns);
    }
    function _testInvalidENS(string memory ens) internal {
        vm.expectRevert();
        ENSDNSCoder.dnsEncode(ens);
    }
    function _testInvalidDNS(bytes memory dns) internal {
        vm.expectRevert();
        ENSDNSCoder.dnsDecode(dns);
    }
}
