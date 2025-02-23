import dotenv from "dotenv";

dotenv.config();

export const config = {
  rpcEndpoint: process.env.RPC_ENDPOINT || "http://localhost:26657",

  contractAddress: process.env.CONTRACT_ADDRESS || "",

  adminMnemonic: process.env.ADMIN_MNEMONIC || "",

  claimCronSchedule: process.env.CLAIM_CRON_SCHEDULE || "0 * * * *",

  logging: {
    level: process.env.LOG_LEVEL || "info",
    file: process.env.LOG_FILE || "reward-claimer.log",
  },
};
