import type { Foundry } from "@adraffy/blocksmith";
import { solidityPackedKeccak256, type BigNumberish } from "ethers";

export const ENS_REGISTRY = "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e";

export const EVM_BIT = 0x8000_0000n;

export function coinTypeFromChain(chain: bigint) {
	return chain == 1n ? 60n : chain | EVM_BIT;
}

export function slugFromCoinType(coinType: bigint) {
	switch (coinType) {
		case EVM_BIT:
			return "default";
		case 60n:
			return "addr";
		default:
			return coinType.toString(16);
	}
}

export function suffixFromCoinType(coinType: bigint) {
	return `${slugFromCoinType(coinType)}.reverse`;
}

export function labelFromAddress(address: string) {
	return address.slice(2).toLowerCase();
}

export function reverseName(address: string, coinType: bigint) {
	return labelFromAddress(address) + "." + suffixFromCoinType(coinType);
}

// export function wrapENS(foundry: Foundry) {
// 	return new Contract(ENS_REGISTRY, [

// 	], foundry.provider);
// }

export async function overrideENS(
	foundry: Foundry,
	node: string,
	{ owner, resolver }: { owner?: BigNumberish; resolver?: BigNumberish }
) {
	const slot = BigInt(
		solidityPackedKeccak256(["bytes32", "uint256"], [node, 0n])
	);
	const owner0 = BigInt(
		await foundry.provider.getStorage(ENS_REGISTRY, slot)
	);
	// https://github.com/foundry-rs/foundry/issues/9743
	await foundry.setStorageValue(ENS_REGISTRY, slot, owner || owner0 || 1);
	await foundry.setStorageValue(ENS_REGISTRY, slot + 1n, resolver || 0);
}
