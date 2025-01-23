import { Foundry } from "@adraffy/blocksmith";
import { createResolve } from "./UR.js";
import { deployUR, testUR } from "./tests.js";
import { afterAll } from "bun:test";
import { describe } from "./describe-fix.js";

describe("WrappedUR", async () => {
	const foundry = await Foundry.launch({
		fork: process.env.PROVIDER,
		infoLog: true,
	});
	afterAll(foundry.shutdown);
	const UR = await deployUR(foundry);
	const WrappedUR = await foundry.deploy({file: "WrappedUR", args: [UR]});
	testUR(createResolve(WrappedUR));
});
