export type ModalKind = "deposit" | "withdraw" | "borrow" | "repay" | "stake" | "unstake" | null;

export interface ToastState {
  title: string;
  body: string;
  color: string;
  glyph: string;
}
