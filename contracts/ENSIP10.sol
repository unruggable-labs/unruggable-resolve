// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ENS} from "@ensdomains/ens-contracts/contracts/registry/ENS.sol";
import {IExtendedResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IExtendedResolver.sol";
import {BytesUtils} from "@ensdomains/ens-contracts/contracts/utils/BytesUtils.sol";
import {ERC165, IERC165} from "./ERC165.sol";

struct Lookup {
    bytes dns;
    uint256 offset; // byte offset into dns
    bytes32 basenode;
    address resolver;
    bool extended; // if true, use resolve()
    bool ok;
}

library ENSIP10 {
    function lookupResolver(
        ENS ens,
        bytes memory dns
    ) internal view returns (Lookup memory lookup) {
        // https://docs.ens.domains/ensip/10
        unchecked {
            lookup.dns = dns;
            while (true) {
                lookup.basenode = BytesUtils.namehash(dns, lookup.offset);
                lookup.resolver = ens.resolver(lookup.basenode);
                if (lookup.resolver != address(0)) break;
                uint256 len = uint8(dns[lookup.offset]);
                if (len == 0) {
                    return lookup;
                }
                lookup.offset += 1 + len;
            }
            if (
                ERC165.supportsInterface(
                    lookup.resolver,
                    type(IExtendedResolver).interfaceId
                )
            ) {
                lookup.extended = true;
                lookup.ok = true;
            } else if (lookup.offset == 0) {
                lookup.ok = true;
            }
        }
    }
}
