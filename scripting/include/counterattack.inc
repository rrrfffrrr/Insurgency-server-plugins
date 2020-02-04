
#if defined _ins_counterattack
 #endinput
#endif
#define _ins_counterattack

/**
 * Called when counter attack has finished.
 * 
 * @param isCustom        Is counter attack occured by plugin or game.
 */
forward void OnCounterAttackFinished(bool isCustom);
// Start counter attack.
native void StartCounterAttack();