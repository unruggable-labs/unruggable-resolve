// TODO: fix me

import { Foundry } from "@adraffy/blocksmith";
import { deployUR } from "./tests.js";
import { RESOLVER_ABI } from "./UR.js";
import { dnsEncode } from "ethers/hash";
import { ZeroHash } from "ethers/constants";

const foundry = await Foundry.launch({
	fork: process.env.PROVIDER,
	infoLog: true,
});

const UR = await deployUR(foundry);

const RR = await foundry.deploy({
	file: "ReverseUR",
	args: [UR],
});

const UniversalResolver = await foundry.deploy({
	file: "UniversalResolver",
	args: [RR],
});

console.log(
	await UniversalResolver.resolve(
		dnsEncode("raffy.eth"),
		RESOLVER_ABI.encodeFunctionData("text", [ZeroHash, "description"]),
		{ enableCcipRead: true }
	)
);

const [answer] = await UniversalResolver.resolve(
	dnsEncode("raffy.eth"),
	RESOLVER_ABI.encodeFunctionData("multicall", [
		[
			RESOLVER_ABI.encodeFunctionData("addr(bytes32)", [ZeroHash]),
			RESOLVER_ABI.encodeFunctionData("text(bytes32,string)", [
				ZeroHash,
				"description",
			]),
		],
	]),
	{ enableCcipRead: true }
);
console.log(RESOLVER_ABI.decodeFunctionResult("multicall", answer));

await foundry.shutdown();
