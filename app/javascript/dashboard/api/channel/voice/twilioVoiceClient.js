// ponytail: @twilio/voice-sdk removed, stub preserves call session consumers
const createCallDisconnectedEvent = () => new CustomEvent('call:disconnected');

class TwilioVoiceClient extends EventTarget {
  constructor() {
    super();
    this.device = null;
    this.activeConnection = null;
    this.initialized = false;
    this.inboxId = null;
  }

  async initializeDevice() {
    return null;
  }

  get hasActiveConnection() {
    return false;
  }

  setMuted() {
    return false;
  }

  endClientCall() {
    this.activeConnection = null;
  }

  destroyDevice() {
    this.activeConnection = null;
    this.device = null;
    this.initialized = false;
    this.inboxId = null;
  }

  async joinClientCall() {
    return null;
  }

  onDisconnect = () => {
    this.activeConnection = null;
    this.dispatchEvent(createCallDisconnectedEvent());
  };
}

export default new TwilioVoiceClient();
