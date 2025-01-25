import { Foundry } from "@adraffy/blocksmith";
import { deployUR, testUR } from "./tests.js";

const foundry = await Foundry.launch({
	infoLog: true,
});

const UR = await deployUR(foundry);

await foundry.deploy({ file: "ReverseUR", args: [UR] });

await foundry.deploy({ file: "HumanUR", args: [UR] });

await foundry.shutdown();
