//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ITextResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/ITextResolver.sol";
import {IAddressResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IAddressResolver.sol";
import {IAddrResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IAddrResolver.sol";
import {IContentHashResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IContentHashResolver.sol";
import {INameResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/INameResolver.sol";
import {IExtendedResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IExtendedResolver.sol";

contract OpenResolver is
    IERC165,
    IAddrResolver,
    IAddressResolver,
    IContentHashResolver,
    ITextResolver,
    IExtendedResolver
{
    struct Record {
        mapping(string => string) texts;
        mapping(uint256 => bytes) addrs;
        bytes contenthash;
        string name;
    }

    bool immutable _extended;
    mapping(bytes32 => Record) _records;

    constructor(bool extended) {
        _extended = extended;
    }

    function supportsInterface(bytes4 x) external view returns (bool) {
        return type(IERC165).interfaceId == x || type(IAddrResolver).interfaceId == x
            || type(IAddressResolver).interfaceId == x || type(ITextResolver).interfaceId == x
            || type(IContentHashResolver).interfaceId == x || type(INameResolver).interfaceId == x
            || (type(IExtendedResolver).interfaceId == x && _extended);
    }

    function resolve(bytes calldata, bytes calldata call) external view returns (bytes memory) {
        (bool ok, bytes memory v) = address(this).staticcall(call);
        if (!ok) {
            assembly {
                revert(add(v, 32), mload(v))
            }
        }
        return v;
    }

    function addr(bytes32 node) external view returns (address payable) {
        return payable(address(bytes20(_records[node].addrs[60])));
    }

    function addr(bytes32 node, uint256 coinType) external view returns (bytes memory) {
        return _records[node].addrs[coinType];
    }

    function text(bytes32 node, string memory key) external view returns (string memory) {
        return _records[node].texts[key];
    }

    function contenthash(bytes32 node) external view returns (bytes memory) {
        return _records[node].contenthash;
    }

    function name(bytes32 node) external view returns (string memory) {
        return _records[node].name;
    }

    function setAddr(bytes32 node, uint256 coinType, bytes memory value) external {
        _records[node].addrs[coinType] = value;
    }

    function setText(bytes32 node, string memory key, string memory value) external {
        _records[node].texts[key] = value;
    }

    function setContenthash(bytes32 node, bytes memory value) external {
        _records[node].contenthash = value;
    }

    function setName(bytes32 node, string memory value) external {
        _records[node].name = value;
    }
}
