# frozen_string_literal: true

describe Ferrum::Contexts do
  def session_callbacks(session_id)
    browser.client.dispatcher.instance_variable_get(:@on).keys.select { |key| key.end_with?("_#{session_id}") }
  end

  describe "#dispose" do
    it "releases the callbacks of a worker the page terminated before" do
      context = browser.contexts.create
      page = context.create_page
      page.go_to
      page.execute <<~JS
        window.worker = new Worker(URL.createObjectURL(new Blob(
          ["self.onmessage = () => {}"],
          { type: "application/javascript" }
        )))
      JS
      wait_for { context.targets.values.find { |target| target.worker? && target.connected? } }.not_to be_nil
      worker = context.targets.values.find(&:worker?)
      session_id = worker.session_id
      expect(session_callbacks(session_id)).not_to be_empty

      page.execute("window.worker.terminate()")
      wait_for { context.target(worker.id) }.to be_nil
      context.dispose

      wait_for { session_callbacks(session_id) }.to be_empty
    end
  end

  describe "#reset" do
    it "forgets a context whose disposal fails and still disposes the others" do
      stuck = browser.contexts.create
      other = browser.contexts.create
      allow(browser.client).to receive(:command).and_call_original
      allow(browser.client).to receive(:command)
        .with("Target.disposeBrowserContext", timeout: anything, browserContextId: stuck.id)
        .and_raise(Ferrum::TimeoutError)

      expect { browser.reset }.to raise_error(Ferrum::TimeoutError)
      expect(browser.contexts[stuck.id]).to be_nil
      expect(browser.contexts[other.id]).to be_nil
      expect(browser.command("Target.getBrowserContexts")["browserContextIds"]).not_to include(other.id)

      allow(browser.client).to receive(:command)
        .with("Target.disposeBrowserContext", timeout: anything, browserContextId: stuck.id)
        .and_raise(Ferrum::BrowserError, { "message" => "Disposal of browser context #{stuck.id} is already pending" })

      expect { browser.reset }.not_to raise_error
    end
  end
end
