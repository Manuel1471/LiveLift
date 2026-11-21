export async function gotoLiveLift(page, path) {
  await page.goto(path);
  await page.waitForFunction(() => window.liveSocket?.isConnected() &&
    [...document.querySelectorAll('[phx-hook="LiveLift"]')].every(
      (island) => island.dataset.liveLiftLoad === "ready"
    ));
}
