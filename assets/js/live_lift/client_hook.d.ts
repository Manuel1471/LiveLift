export type ClientValue =
  | null
  | boolean
  | number
  | string
  | readonly ClientValue[]
  | { readonly [key: string]: ClientValue };

export type ClientState = Readonly<Record<string, ClientValue>>;

export interface ClientEvent {
  readonly value: string | null;
  readonly checked: boolean;
  readonly params: Readonly<Record<string, ClientValue>>;
}

export interface ClientView {
  readonly actions: Readonly<Record<string, (state: ClientState, event: ClientEvent) => ClientState>>;
  readonly template: string | readonly unknown[];
}

export type ViewRegistry = Readonly<Record<string, ClientView | ViewLoader>>;
export type ViewLoader = () => Promise<{ readonly views: ViewRegistry }>;

export interface LiveLiftHook {
  mounted(): void | Promise<void>;
  updated(): void;
  destroyed(): void;
  disconnected(): void;
  reconnected(): void;
}

export declare function createClientHook(views: ViewRegistry): LiveLiftHook;
