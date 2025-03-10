import { Foundry } from "@adraffy/blocksmith";
import { createResolve } from "./UR.js";
import { afterAll } from "bun:test";
import { describe } from "./describe-fix.js";
import { deployUR, testUR } from "./tests.js";

describe("UR", async () => {
	const foundry = await Foundry.launch({
		fork: process.env.PROVIDER,
		infoLog: false,
	});
	afterAll(foundry.shutdown);
	const UR = await deployUR(foundry);
	testUR(createResolve(UR));
});
