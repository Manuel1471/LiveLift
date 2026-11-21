import {expect, test} from "@playwright/test";
import {gotoLiveLift, measureCounterClick} from "./support.mjs";

test("event measurement separates the optimistic update and Phoenix acknowledgment", async ({page}) => {
  await gotoLiveLift(page, "/native-counter-server");
  const server = await measureCounterClick(page, false);
  expect(server.confirmedMs).toBe(server.visibleMs);

  let release;
  await page.routeWebSocket(/\/live\/websocket/, (browser) => {
    const server = browser.connectToServer();
    browser.onMessage((message) => {
      const event = typeof message === "string" ? JSON.parse(message)?.[4]?.event : undefined;
      if (event === "inc") {
        release = () => server.send(message);
      } else {
        server.send(message);
      }
    });
  });
  await gotoLiveLift(page, "/native-counter");
  const island = page.locator("#native-counter");
  const [client] = await Promise.all([
    measureCounterClick(page, true),
    (async () => {
      await expect.poll(() => Boolean(release)).toBe(true);
      await expect(island.locator("output")).toHaveText("1");
      await expect(island).toHaveAttribute("data-live-lift-ack-seq", "0");
      release();
    })(),
  ]);
  expect(client.confirmedMs).toBeGreaterThan(client.visibleMs);
  await expect(island).toHaveAttribute("data-live-lift-ack-seq", "1");
});
