import { Foundry } from "@adraffy/blocksmith";
import { deployUR } from "./tests.js";
import {
	coinTypeFromChain,
	EVM_BIT,
	overrideENS,
	reverseName,
	suffixFromCoinType,
} from "./ens.js";
import { type URLookup } from "./UR.js";
import { test, afterAll, expect } from "bun:test";
import { describe } from "./describe-fix.js";
import { dnsEncode, namehash } from "ethers";

describe("ReverseUR", async () => {
	const foundry = await Foundry.launch({
		fork: process.env.PROVIDER,
		infoLog: false,
	});
	afterAll(foundry.shutdown);

	const UR = await deployUR(foundry);
	const ReverseUR = await foundry.deploy({ file: "ReverseUR", args: [UR] });

	async function reverse(address: string, coinType: bigint) {
		const res = await ReverseUR.reverse(address, coinType, [], {
			enableCcipRead: true,
		});
		return {
			rev: res[0].toObject() as URLookup,
			fwd: res[1].toObject() as URLookup,
			answer: res[2] as string,
		};
	}

	// function testReverse(name: string, addr: string, coinType0: bigint, coinType: bigint) {
	// 	test(`${reverse(addr, coinType0)} => ${slugFromCoinType(coinType)}`, () => {
	// 		expect(reverse(addr, coinType0)).resolves.toMatchObject({
	// 			rev: {
	// 				dns: dnsEncode(reverseName(addr, coinType)),
	// 			},
	// 			fwd: {
	// 				dns: dnsEncode(name),
	// 			},
	// 			answer: addr.toLowerCase(),
	// 		});
	// 	});
	// }

	const ForwardResolver = await foundry.deploy({
		file: "OpenResolver",
		args: [false],
	});

	const DefaultResolver = await foundry.deploy({
		file: "OpenResolver",
		args: [true],
	});
	await overrideENS(foundry, namehash(suffixFromCoinType(EVM_BIT)), {
		resolver: DefaultResolver.target,
	});

	const BASE = 8453n;
	const BaseResolver = await foundry.deploy({
		file: "OpenResolver",
		args: [true],
	});
	await overrideENS(
		foundry,
		namehash(suffixFromCoinType(coinTypeFromChain(BASE))),
		{
			resolver: BaseResolver.target,
		}
	);

	const A_ADDR = "0xC973b97c1F8f9E3b150E2C12d4856A24b3d563cb";
	const A_NAME = "adraffy.cb.id";

	const B_ADDR = "0x51050ec063d393217B436747617aD1C2285Aeeee";
	const B_NAME = "raffy.eth";
	await foundry.confirm(
		DefaultResolver.setName(
			namehash(reverseName(B_ADDR, coinTypeFromChain(EVM_BIT))),
			B_NAME
		)
	);

	const C_ADDR = foundry.wallets.admin.address;
	const C_NAME = "chonk.chonk";
	await foundry.confirm(
		BaseResolver.setName(
			namehash(reverseName(C_ADDR, coinTypeFromChain(BASE))),
			C_NAME
		)
	);
	await overrideENS(foundry, namehash(C_NAME), {
		resolver: ForwardResolver.target,
	});
	await foundry.confirm(
		ForwardResolver.setAddr(
			namehash(C_NAME),
			coinTypeFromChain(BASE),
			C_ADDR
		)
	);

	test("A.addr => use addr", () => {
		expect(reverse(A_ADDR, coinTypeFromChain(1n))).resolves.toMatchObject({
			rev: {
				dns: dnsEncode(reverseName(A_ADDR, coinTypeFromChain(1n))),
				extended: true,
			},
			fwd: {
				dns: dnsEncode(A_NAME),
				extended: false,
			},
			answer: A_ADDR.toLowerCase(),
		});
	});

	test("B.base => use default", () => {
		expect(reverse(B_ADDR, coinTypeFromChain(BASE))).resolves.toMatchObject(
			{
				rev: {
					dns: dnsEncode(reverseName(B_ADDR, EVM_BIT)),
					extended: true,
				},
				fwd: {
					dns: dnsEncode(B_NAME),
					extended: true,
				},
				answer: B_ADDR.toLowerCase(),
			}
		);
	});

	test("C.base => use base", () => {
		expect(reverse(C_ADDR, coinTypeFromChain(BASE))).resolves.toMatchObject(
			{
				rev: {
					dns: dnsEncode(
						reverseName(C_ADDR, coinTypeFromChain(BASE))
					),
					extended: true,
				},
				fwd: {
					dns: dnsEncode(C_NAME),
					extended: false,
				},
				answer: C_ADDR.toLowerCase(),
			}
		);
	});
});
