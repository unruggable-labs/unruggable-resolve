import { Foundry } from "@adraffy/blocksmith";
import { deployUR } from "./tests.js";

const foundry = await Foundry.launch({ infoLog: false });

const report: Record<string, bigint> = {};
foundry.on("deploy", (c) => (report[c.__info.contract] = c.__receipt.gasUsed));

const UR = await deployUR(foundry);
const RR = await foundry.deploy({ file: "ReverseUR", args: [UR] });
await foundry.deploy({ file: "UnruggableUR", args: [UR] });
await foundry.deploy({ file: "UniversalResolver", args: [RR] });
await foundry.deploy({ file: "UniversalResolverOld", args: [UR] });
await foundry.shutdown();

console.log(report);
