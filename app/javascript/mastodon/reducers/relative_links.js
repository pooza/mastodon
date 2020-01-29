import Immutable from 'immutable';
import { TOGGLE_RELATIVE_LINKS } from '../actions/relative_links';

const initialState = Immutable.Map({
  visible: true,
});

export default function announcements(state = initialState, action) {
  switch(action.type) {
  case TOGGLE_RELATIVE_LINKS:
    return state.set('visible', !state.get('visible'));
  default:
    return state;
  }
};