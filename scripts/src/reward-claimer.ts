import { CronJob } from "cron";
import axios from "axios";
import { config } from "./config";
import fs from "fs";

class RewardClaimer {
  private logger: any;

  constructor() {
    this.setupLogger();
  }

  private setupLogger() {
    // Create log file stream
    const logStream = fs.createWriteStream(config.logging.file, { flags: "a" });

    this.logger = {
      info: (message: string) => {
        const logMessage = `[${new Date().toISOString()}] INFO: ${message}\n`;
        console.log(logMessage);
        logStream.write(logMessage);
      },
      error: (message: string) => {
        const logMessage = `[${new Date().toISOString()}] ERROR: ${message}\n`;
        console.error(logMessage);
        logStream.write(logMessage);
      },
    };
  }

  private async canClaimRewards(): Promise<boolean> {
    try {
      const response = await axios.post(config.rpcEndpoint, {
        jsonrpc: "2.0",
        id: 1,
        method: "abci_query",
        params: {
          path: "/custom/liquid_staking/can_claim_rewards",
          data: Buffer.from(config.contractAddress).toString("hex"),
        },
      });

      if (response.data.result.response.value) {
        const result = JSON.parse(
          Buffer.from(response.data.result.response.value, "base64").toString()
        );
        return result.can_claim;
      }
      return false;
    } catch (error) {
      this.logger.error(`Error checking reward claim availability: ${error}`);
      return false;
    }
  }

  private async claimRewards() {
    try {
      // Check if rewards can be claimed
      const canClaim = await this.canClaimRewards();
      if (!canClaim) {
        this.logger.info(
          "Cannot claim rewards yet - waiting for next interval"
        );
        return;
      }

      // Execute reward claim transaction
      const response = await axios.post(config.rpcEndpoint, {
        jsonrpc: "2.0",
        id: 1,
        method: "broadcast_tx_sync",
        params: {
          tx: {
            type: "liquid_staking/try_claim_rewards",
            value: {
              admin: config.adminMnemonic, // Should generate address from mnemonic in production
            },
          },
        },
      });

      if (response.data.result.code === 0) {
        this.logger.info(
          `Reward claim successful! TxHash: ${response.data.result.hash}`
        );
      } else {
        this.logger.error(`Reward claim failed: ${response.data.result.log}`);
      }
    } catch (error) {
      this.logger.error(`Error during reward claim: ${error}`);
    }
  }

  public start() {
    this.logger.info("Starting reward claim automation system");

    // Start cron job - runs once per day at 00:00 UTC
    const job = new CronJob(
      config.claimCronSchedule,
      () => this.claimRewards(),
      null,
      true,
      "UTC"
    );

    this.logger.info(`Next reward claim scheduled for: ${job.nextDates()}`);
  }
}

// Initialize and start the reward claimer
const claimer = new RewardClaimer();
claimer.start();
