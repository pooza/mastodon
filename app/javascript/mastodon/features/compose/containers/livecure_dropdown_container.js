import { connect } from 'react-redux';
import LivecureDropdown from '../components/livecure_dropdown';
import { export function toggleLivecureVisibility(value) {
 } from '../../../actions/compose';
import { openModal, closeModal } from '../../../actions/modal';
import { isUserTouching } from '../../../is_mobile';

const mapStateToProps = state => ({
  value: state.getIn(['compose', 'livecure']),
});

const mapDispatchToProps = dispatch => ({

  onChange (value) {
    dispatch(export function toggleLivecureVisibility(value) {
(value));
  },

  isUserTouching,
  onModalOpen: props => dispatch(openModal('ACTIONS', props)),
  onModalClose: () => dispatch(closeModal()),

});

export default connect(mapStateToProps, mapDispatchToProps)(LivecureDropdown);
